#!/usr/bin/env python3
"""
Cisco XDR/Workflows Remote Appliance Local Registration Script
v1.3 - 15-Jan-2026
Author: Steve Holl [sholl@cisco.com]

This script registers a Cisco XDR/Workflows Remote Appliance by:
1. Prompting for the base64 OVF user-data string
2. Extracting values.yaml and ca-key-pair.yaml from cloud-config
3. Checking for existing containers and offering to clean up
4. Checking IPv4 forwarding and offering to enable it
5. Writing configuration files to /etc/ao-remote/
6. Running the docker-compose-init.sh script
7. Verifying registration with MQTT heartbeat confirmation

Features:
- Handles base64 padding issues automatically
- Detects certificate data in files with empty paths
- Normalizes YAML structure for compatibility
- Checks and enables IPv4 forwarding for Docker networking
- Detects existing registrations and offers clean re-registration
- Fully repeatable for lab environments without needing
  the user encoded-data into the OVF, which some virtualization
  environments don't support
- Verifies MQTT heartbeat via syslog before claiming success (v1.2)
- Detects container restart loops and provides diagnostics (v1.2)
- Works with syslog logging driver (reads from journalctl/syslog) (v1.2)
- Cleans old certificates on re-registration to prevent stale credential issues (v1.3)

Usage (run directly on the appliance):
    sudo python3 register-local.py

Or non-interactive:
    sudo python3 register-local.py <base64_string>
    sudo python3 register-local.py remotePackage.zip
"""

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

import yaml


class LocalXDRRegistration:
    """Handles local XDR appliance registration"""

    def __init__(self, ovf_base64_string):
        self.ovf_base64 = ovf_base64_string.strip()
        self.cloud_config = None
        self.values_yaml = None
        self.ca_key_pair_yaml = None

    def decode_ovf_string(self):
        """Decode base64 OVF user-data string"""
        print("[*] Decoding OVF user-data string...")
        try:
            # Clean the input - remove whitespace and newlines
            clean_base64 = "".join(self.ovf_base64.split())

            # Try to decode with padding correction
            try:
                decoded = base64.b64decode(clean_base64)
            except Exception:
                # If it fails, try adding padding
                missing_padding = len(clean_base64) % 4
                if missing_padding:
                    clean_base64 += "=" * (4 - missing_padding)
                decoded = base64.b64decode(clean_base64)

            self.cloud_config = yaml.safe_load(decoded)
            print("[+] Successfully decoded cloud-config")
            return True
        except Exception as e:
            print(f"[!] Error decoding OVF string: {e}", file=sys.stderr)
            print(f"[!] Base64 string length: {len(self.ovf_base64)}")
            print(f"[!] First 50 chars: {self.ovf_base64[:50]}")
            return False

    def extract_yaml_files(self):
        """Extract values.yaml and ca-key-pair.yaml from cloud-config"""
        print("[*] Extracting YAML configuration files...")

        if "write_files" not in self.cloud_config:
            print("[!] No write_files section found in cloud-config", file=sys.stderr)
            return False

        # First, show what files are available
        print("[*] Files found in cloud-config:")
        for file_entry in self.cloud_config["write_files"]:
            path = file_entry.get("path", "")
            print(f"    - {path}")

        # Now extract them
        for file_entry in self.cloud_config["write_files"]:
            path = file_entry.get("path", "")
            content = file_entry.get("content", "")

            if "values.yaml" in path:
                self.values_yaml = content
                print(f"[+] Found values.yaml at: {path}")
            elif "ca-key-pair.yaml" in path or "ca_key_pair.yaml" in path:
                self.ca_key_pair_yaml = content
                print(f"[+] Found ca-key-pair.yaml at: {path}")
            elif not path and content:
                # Handle files with missing/empty path - detect by content
                if (
                    "ca.crt:" in content
                    or "tls.key:" in content
                    or "tls.crt:" in content
                ):
                    self.ca_key_pair_yaml = content
                    print(
                        "[+] Found ca-key-pair.yaml (path was empty, detected by certificate content)"
                    )
                elif (
                    "remote_name:" in content
                    or "remote_id:" in content
                    or "mqtt_broker:" in content
                ):
                    self.values_yaml = content
                    print(
                        "[+] Found values.yaml (path was empty, detected by environment content)"
                    )

        if not self.values_yaml or not self.ca_key_pair_yaml:
            print("[!] Missing required YAML files in cloud-config", file=sys.stderr)
            if not self.values_yaml:
                print("[!]   - values.yaml not found")
            if not self.ca_key_pair_yaml:
                print("[!]   - ca-key-pair.yaml not found")
            return False

        return True

    def display_config_info(self):
        """Display configuration information extracted from values.yaml"""
        try:
            values_data = yaml.safe_load(self.values_yaml)
            env = values_data.get("env", {})

            print("\n" + "=" * 70)
            print("XDR Remote Appliance Configuration")
            print("=" * 70)
            print(f"Remote Name:     {env.get('remote_name', 'N/A')}")
            print(f"Remote ID:       {env.get('remote_id', 'N/A')}")
            print(f"MQTT Broker:     {env.get('mqtt_broker', 'N/A')}")
            print(f"Proxy:           {env.get('all_proxy', '(none)')}")
            print("=" * 70 + "\n")
        except Exception as e:
            print(f"[!] Could not parse values.yaml for display: {e}")

    def normalize_ca_key_pair_yaml(self) -> str:
        """Ensure ca-key-pair.yaml has the correct structure for extract_yaml.py"""
        if not self.ca_key_pair_yaml:
            return ""

        try:
            ca_data = yaml.safe_load(self.ca_key_pair_yaml)

            # Debug: Show what keys we have in the raw data
            print(f"[*] Raw certificate data keys: {list(ca_data.keys())}")

            # Check if it already has the expected structure (data.tls.crt, etc.)
            if "data" in ca_data and "tls.crt" in ca_data["data"]:
                # Already in correct format
                return self.ca_key_pair_yaml

            # If it has the flat structure (ca.crt, tls.key, tls.crt at top level)
            # Transform it to the expected nested structure
            if "ca.crt" in ca_data or "tls.crt" in ca_data or "tls.key" in ca_data:
                normalized = {
                    "data": {
                        "ca.crt": ca_data.get("ca.crt", ""),
                        "tls.crt": ca_data.get("tls.crt", ""),
                        "tls.key": ca_data.get("tls.key", ""),
                    }
                }

                # Debug: Show what we're including
                for key in ["ca.crt", "tls.crt", "tls.key"]:
                    if key in ca_data:
                        print(f"[*]   {key}: present ({len(ca_data[key])} chars)")
                    else:
                        print(f"[!]   {key}: MISSING from source data")

                print("[*] Normalized ca-key-pair.yaml structure to expected format")
                # Use width parameter to prevent line wrapping of long base64 strings
                return yaml.dump(
                    normalized, default_flow_style=False, width=float("inf")
                )

            # Return as-is if we can't determine the structure
            return self.ca_key_pair_yaml

        except Exception as e:
            print(f"[!] Warning: Could not normalize ca-key-pair.yaml: {e}")
            return self.ca_key_pair_yaml if self.ca_key_pair_yaml else ""

    def write_config_files(self):
        """Write YAML files to /etc/ao-remote/"""
        print("[*] Writing configuration files to /etc/ao-remote/...")

        target_dir = Path("/etc/ao-remote")

        try:
            # Create directory if it doesn't exist
            target_dir.mkdir(parents=True, exist_ok=True)
            os.chmod(target_dir, 0o700)

            # Write values.yaml
            values_path = target_dir / "values.yaml"
            with open(values_path, "w") as f:
                f.write(self.values_yaml)
            os.chmod(values_path, 0o600)
            print(f"[+] Written: {values_path}")

            # Normalize and write ca-key-pair.yaml
            normalized_ca_key_pair = self.normalize_ca_key_pair_yaml()
            ca_key_pair_path = target_dir / "ca-key-pair.yaml"
            with open(ca_key_pair_path, "w") as f:
                f.write(normalized_ca_key_pair)
            os.chmod(ca_key_pair_path, 0o600)
            print(f"[+] Written: {ca_key_pair_path}")

            print("[+] Configuration files written successfully\n")
            return True

        except PermissionError:
            print("[!] Permission denied. Please run with sudo", file=sys.stderr)
            return False
        except Exception as e:
            print(f"[!] Error writing files: {e}", file=sys.stderr)
            return False

    def check_existing_registration(self):
        """Check if containers are already running and offer to clean up"""
        try:
            result = subprocess.run(
                ["docker", "ps", "-q", "-f", "name=xdr-automation"],
                capture_output=True,
                text=True,
            )

            if result.stdout.strip():
                print("\n[!] Existing XDR containers are already running")
                print(
                    "[*] Would you like to stop and remove them before re-registering? (yes/no)"
                )
                response = input("> ").strip().lower()

                if response in ["yes", "y"]:
                    print("[*] Stopping containers...")
                    subprocess.run(
                        [
                            "docker",
                            "compose",
                            "-f",
                            "/etc/docker-compose/docker-compose.yaml",
                            "down",
                        ],
                        check=False,
                    )
                    print("[+] Containers stopped and removed")

                    # Remove old certificates to force regeneration with new credentials
                    secrets_dir = Path("/etc/docker-compose/secrets")
                    if secrets_dir.exists():
                        print("[*] Removing old certificates to force regeneration...")
                        try:
                            shutil.rmtree(secrets_dir)
                            print("[+] Old certificates removed")
                        except Exception as e:
                            print(f"[!] Warning: Could not remove old certificates: {e}")

                    return True
                else:
                    print(
                        "[!] Warning: Registration may fail with existing containers running"
                    )
                    print("[*] Continue anyway? (yes/no)")
                    response = input("> ").strip().lower()
                    return response in ["yes", "y"]

            return True

        except Exception as e:
            print(f"[!] Could not check for existing containers: {e}")
            return True  # Don't block registration

    def check_ipv4_forwarding(self):
        """Check if IPv4 forwarding is enabled and offer to enable it"""
        try:
            result = subprocess.run(
                ["sysctl", "net.ipv4.ip_forward"], capture_output=True, text=True
            )

            if "net.ipv4.ip_forward = 0" in result.stdout:
                print("\n[!] IPv4 forwarding is currently disabled")
                print("[*] Docker containers require IPv4 forwarding for networking")
                print("\nWould you like to enable IPv4 forwarding now? (yes/no)")
                response = input("> ").strip().lower()

                if response in ["yes", "y"]:
                    # Enable immediately
                    subprocess.run(
                        ["sudo", "sysctl", "-w", "net.ipv4.ip_forward=1"], check=True
                    )

                    # Make it persistent across reboots
                    sysctl_conf = "/etc/sysctl.conf"
                    with open(sysctl_conf, "r") as f:
                        content = f.read()

                    if "net.ipv4.ip_forward=1" not in content:
                        with open(sysctl_conf, "a") as f:
                            f.write("\n# Enable IPv4 forwarding for Docker\n")
                            f.write("net.ipv4.ip_forward=1\n")

                    print("[+] IPv4 forwarding enabled")
                    return True
                else:
                    print("[!] Warning: Containers may not have network connectivity")
                    return True
            else:
                print("[+] IPv4 forwarding is already enabled")
                return True

        except Exception as e:
            print(f"[!] Could not check IPv4 forwarding: {e}")
            return True  # Don't block registration

    def _read_syslog_entries(self, container_name: str, since_seconds: int = 300) -> list:
        """
        Read syslog entries for a specific container.
        Since docker logs doesn't work with syslog driver, read from system logs.

        Args:
            container_name: Name of the container (e.g., 'ao-remote-1')
            since_seconds: How far back to look (default 5 minutes)

        Returns:
            List of log lines matching the container
        """
        # Try journalctl first (systemd systems)
        logs = self._read_syslog_journalctl(container_name, since_seconds)
        if logs:
            return logs

        # Fallback to /var/log/syslog
        return self._read_syslog_file(container_name)

    def _read_syslog_journalctl(self, container_name: str, since_seconds: int = 300) -> list:
        """Read logs using journalctl (systemd)."""
        try:
            since_minutes = max(1, since_seconds // 60)
            result = subprocess.run(
                [
                    "journalctl",
                    f"CONTAINER_NAME={container_name}",
                    "--since", f"{since_minutes} minutes ago",
                    "--no-pager",
                    "-o", "short-iso"
                ],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip().split('\n')
            return []
        except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
            return []

    def _read_syslog_file(self, container_name: str, max_lines: int = 200) -> list:
        """Read logs from /var/log/syslog or /var/log/messages."""
        syslog_paths = ["/var/log/syslog", "/var/log/messages"]

        for syslog_path in syslog_paths:
            if os.path.exists(syslog_path):
                try:
                    result = subprocess.run(
                        ["grep", "-i", container_name, syslog_path],
                        capture_output=True,
                        text=True,
                        timeout=30
                    )
                    if result.stdout.strip():
                        lines = result.stdout.strip().split('\n')
                        return lines[-max_lines:] if len(lines) > max_lines else lines
                except (subprocess.TimeoutExpired, Exception):
                    continue
        return []

    def _get_container_health_status(self, container_name: str) -> dict:
        """
        Get detailed container health and status information.

        Returns:
            Dict with keys: running, health_status, restart_count, exit_code, status
        """
        try:
            result = subprocess.run(
                ["docker", "inspect", "--format", "{{json .State}}", container_name],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                state = json.loads(result.stdout.strip())
                # Also get restart count from top level
                restart_result = subprocess.run(
                    ["docker", "inspect", "--format", "{{.RestartCount}}", container_name],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                restart_count = int(restart_result.stdout.strip()) if restart_result.returncode == 0 else 0

                return {
                    "running": state.get("Running", False),
                    "status": state.get("Status", "unknown"),
                    "health_status": state.get("Health", {}).get("Status", "none"),
                    "restart_count": restart_count,
                    "exit_code": state.get("ExitCode", -1),
                }
        except (subprocess.TimeoutExpired, json.JSONDecodeError, ValueError, Exception):
            pass

        return {
            "running": False,
            "status": "unknown",
            "health_status": "unknown",
            "restart_count": 0,
            "exit_code": -1,
        }

    def _detect_restart_loop(self, container_name: str, threshold: int = 3) -> tuple:
        """
        Detect if container is in a restart loop.

        Args:
            container_name: Container to check
            threshold: Number of restarts considered a loop

        Returns:
            Tuple of (is_looping: bool, restart_count: int)
        """
        status = self._get_container_health_status(container_name)
        restart_count = status.get("restart_count", 0)
        is_looping = restart_count >= threshold
        return (is_looping, restart_count)

    def _check_mqtt_heartbeat_success(self, timeout_seconds: int = 120, poll_interval: int = 5) -> tuple:
        """
        Check container health status to verify MQTT connectivity.

        The ao-remote container's health check verifies MQTT connection.
        Health = "healthy" means MQTT is connected.

        Args:
            timeout_seconds: Maximum time to wait for healthy status
            poll_interval: How often to check health

        Returns:
            Tuple of (success: bool, message: str)
        """
        start_time = time.time()

        while (time.time() - start_time) < timeout_seconds:
            elapsed = int(time.time() - start_time)
            print(f"    Checking container health... ({elapsed}s / {timeout_seconds}s)", end='\r')

            status = self._get_container_health_status("xdr-automation-ao-remote-1")
            health = status.get("health_status", "unknown")

            if health == "healthy":
                print()  # Clear progress line
                return (True, "Container health check passed - MQTT connected")
            elif health == "unhealthy":
                print()  # Clear progress line
                return (False, "Container health check failed - MQTT not connected")
            # "starting" or "none" - keep waiting

            # Also check for restart loops
            is_looping, restart_count = self._detect_restart_loop("xdr-automation-ao-remote-1", threshold=3)
            if is_looping:
                print()
                return (False, f"Container restart loop detected ({restart_count} restarts)")

            time.sleep(poll_interval)

        print()  # Clear progress line
        return (False, f"Timeout ({timeout_seconds}s) - container health still 'starting'")

    def _get_container_error_summary(self, container_name: str) -> str:
        """
        Parse syslog for common errors and return human-readable cause.

        Returns:
            Summary string describing the likely issue
        """
        logs = self._read_syslog_entries(container_name, since_seconds=600)
        log_text = '\n'.join(logs).lower()

        # Check for common error patterns
        if re.search(r"certificate|ssl|tls", log_text):
            return "Certificate/TLS validation issue - check ca-key-pair.yaml"
        if re.search(r"dns|resolve|name.*not.*found", log_text):
            return "DNS resolution failed - check network connectivity"
        if re.search(r"connection refused", log_text):
            return "Connection refused - check MQTT broker port 8883"
        if re.search(r"auth|permission|denied", log_text):
            return "Authentication/permission error - check credentials"
        if re.search(r"timeout", log_text):
            return "Connection timeout - check network/firewall"

        return "Unknown error - review logs for details"

    def _print_diagnostic_commands(self):
        """Print helpful diagnostic commands for troubleshooting."""
        print("\n" + "=" * 70)
        print("DIAGNOSTIC COMMANDS")
        print("=" * 70)
        print("\nSince docker logs doesn't work (syslog driver), use these commands:")
        print("\n1. View ao-remote logs via journalctl:")
        print("   sudo journalctl CONTAINER_NAME=xdr-automation-ao-remote-1 --since '10 minutes ago'")
        print("\n2. View ao-remote logs via syslog:")
        print("   sudo grep 'ao-remote' /var/log/syslog | tail -50")
        print("\n3. Check container status:")
        print("   docker inspect xdr-automation-ao-remote-1 --format='{{json .State}}'")
        print("\n4. Check container restart count:")
        print("   docker inspect xdr-automation-ao-remote-1 --format='{{.RestartCount}}'")
        print("\n5. Test MQTT broker connectivity:")
        print("   openssl s_client -connect <mqtt_broker>:8883 -servername <mqtt_broker>")
        print("=" * 70)

    def _check_containers_running(self) -> bool:
        """Check if XDR containers are running."""
        try:
            result = subprocess.run(
                ["docker", "ps", "-q", "-f", "name=xdr-automation"],
                capture_output=True,
                text=True,
            )
            return bool(result.stdout.strip())
        except Exception:
            return False

    def clean_old_certificates(self):
        """Remove old certificates to force regeneration with new credentials"""
        secrets_dir = Path("/etc/docker-compose/secrets")
        if secrets_dir.exists():
            print("[*] Removing old certificates to force regeneration...")
            try:
                shutil.rmtree(secrets_dir)
                print("[+] Old certificates removed")
                return True
            except Exception as e:
                print(f"[!] Warning: Could not remove old certificates: {e}")
                return False
        return True

    def run_registration(self):
        """Run the docker-compose-init.sh script"""
        init_script = "/usr/local/bin/docker-compose-init.sh"

        if not os.path.exists(init_script):
            print(f"[!] Registration script not found: {init_script}", file=sys.stderr)
            return False

        print("[*] Starting registration process...")
        print("[*] Running: sudo /usr/local/bin/docker-compose-init.sh")
        print("-" * 70)

        try:
            result = subprocess.run(
                ["sudo", init_script], capture_output=False, text=True
            )

            if result.returncode == 0:
                print("\n[+] Docker initialization complete")
                print("[*] Proceeding to verify MQTT connectivity...")
                return True
            else:
                print(
                    f"\n[!] Registration script exited with code: {result.returncode}"
                )
                return False

        except Exception as e:
            print(f"[!] Error running registration script: {e}", file=sys.stderr)
            return False

    def verify_registration(self) -> bool:
        """
        Verify registration by checking:
        1. Docker containers are running
        2. No restart loops detected
        3. MQTT heartbeat is successful (via syslog)

        Returns:
            True if registration is fully successful, False otherwise
        """
        print("\n[*] Verifying registration...")

        # Step 1: Check if containers are running
        print("[*] Step 1/3: Checking container status...")
        try:
            result = subprocess.run(
                ["docker", "ps", "--format", "table {{.Names}}\t{{.Status}}"],
                capture_output=True,
                text=True,
            )

            if result.returncode == 0:
                print("\nDocker Containers:")
                print(result.stdout)
        except Exception as e:
            print(f"[!] Could not check containers: {e}")

        if not self._check_containers_running():
            print("[!] No XDR containers are running")
            self._print_diagnostic_commands()
            return False

        # Step 2: Check for restart loops (especially ao-remote)
        print("[*] Step 2/3: Checking for restart loops...")
        is_looping, restart_count = self._detect_restart_loop("xdr-automation-ao-remote-1", threshold=3)
        if is_looping:
            print(f"[!] WARNING: ao-remote-1 container is restart looping ({restart_count} restarts)")
            error_summary = self._get_container_error_summary("ao-remote")
            print(f"[!] Likely cause: {error_summary}")
            self._print_diagnostic_commands()
            return False
        else:
            print(f"[+] Container restart count: {restart_count} (OK)")

        # Step 3: Wait for container to become healthy (verifies MQTT connection)
        print("[*] Step 3/3: Waiting for container health check...")
        print("    (This may take up to 2 minutes)")
        success, message = self._check_mqtt_heartbeat_success(timeout_seconds=120)

        if success:
            print(f"[+] {message}")
            return True
        else:
            print(f"[!] {message}")
            self._print_diagnostic_commands()
            return False


def extract_base64_from_zip(zip_path: str) -> str:
    """
    Extract base64 string from a remotePackage.zip file.

    The zip file contains a .txt file with the base64-encoded cloud-config.

    Args:
        zip_path: Path to the zip file

    Returns:
        The base64 string, or None if extraction fails
    """
    try:
        print(f"[*] Extracting base64 from zip file: {zip_path}")

        with zipfile.ZipFile(zip_path, 'r') as zf:
            # Find the .txt file in the zip
            txt_files = [f for f in zf.namelist() if f.endswith('.txt')]

            if not txt_files:
                print("[!] No .txt file found in zip archive", file=sys.stderr)
                return None

            # Use the first .txt file found
            txt_file = txt_files[0]
            print(f"[+] Found config file: {txt_file}")

            # Read the content
            content = zf.read(txt_file).decode('utf-8').strip()

            if content.startswith('I2Nsb3Vk'):
                print("[+] Successfully extracted base64 string from zip")
                return content
            else:
                print("[!] File content does not appear to be valid base64 cloud-config", file=sys.stderr)
                return None

    except zipfile.BadZipFile:
        print(f"[!] Invalid zip file: {zip_path}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"[!] Error extracting from zip: {e}", file=sys.stderr)
        return None


def get_base64_input():
    """Prompt user for base64 string"""
    print("=" * 70)
    print("Cisco XDR Remote Appliance Registration")
    print("=" * 70)
    print("\nRECOMMENDED: Use the zip file directly to avoid character truncation:")
    print("    ./register_remote.py remotePackage.zip")
    print("\nAlternatively, paste the base64 OVF user-data string below.")
    print("(It should be a long string starting with 'I2Nsb3VkLWNvbmZpZwo...')")
    print("\nPaste the string and press Enter:")

    base64_string = input("> ").strip()

    if not base64_string:
        print("[!] No input provided", file=sys.stderr)
        return None

    return base64_string


def clear_registration():
    """Clear existing registration by stopping and removing containers."""
    print("=" * 70)
    print("Clearing XDR Remote Appliance Registration")
    print("=" * 70)

    docker_compose_file = "/etc/docker-compose/docker-compose.yaml"

    # Check if docker-compose file exists
    if not os.path.exists(docker_compose_file):
        print("[!] No registration found (docker-compose.yaml does not exist)")
        return True

    # Check for running containers
    try:
        result = subprocess.run(
            ["docker", "ps", "-q", "-f", "name=xdr-automation"],
            capture_output=True,
            text=True,
        )
        if not result.stdout.strip():
            print("[*] No XDR containers are currently running")
        else:
            print("[*] Found running XDR containers")
    except Exception as e:
        print(f"[!] Could not check containers: {e}")

    # Stop and remove containers
    print("[*] Stopping and removing containers...")
    try:
        result = subprocess.run(
            ["docker", "compose", "-f", docker_compose_file, "down", "--remove-orphans"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            print("[+] Containers stopped and removed")
        else:
            print(f"[!] docker compose down returned: {result.returncode}")
            if result.stderr:
                print(f"    {result.stderr.strip()}")
    except Exception as e:
        print(f"[!] Error stopping containers: {e}")

    # Remove old certificates to force regeneration on next registration
    secrets_dir = Path("/etc/docker-compose/secrets")
    if secrets_dir.exists():
        print("[*] Removing old certificates...")
        try:
            shutil.rmtree(secrets_dir)
            print("[+] Old certificates removed")
        except Exception as e:
            print(f"[!] Could not remove certificates: {e}")

    # Optionally clean up config files
    config_dir = Path("/etc/ao-remote")
    if config_dir.exists():
        print(f"[*] Configuration files remain in {config_dir}")
        print("[*] Remove manually if needed: sudo rm -rf /etc/ao-remote")

    print("\n[+] Registration cleared successfully")
    print("[*] You can now re-register with a new configuration")
    return True


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Cisco XDR/Workflows Remote Appliance Registration Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s remotePackage.zip         Register using zip file (RECOMMENDED)
  %(prog)s <base64_string>           Register using base64 string directly
  %(prog)s                           Interactive mode - prompts for input
  %(prog)s -c                        Clear existing registration

NOTE: Using the zip file is recommended to avoid character truncation
      that can occur when pasting long base64 strings interactively.
        """
    )

    parser.add_argument(
        'input',
        nargs='?',
        help='Base64 string or path to remotePackage.zip file'
    )

    parser.add_argument(
        '-c', '--clear',
        action='store_true',
        help='Clear existing registration (stop and remove containers)'
    )

    return parser.parse_args()


def main():
    # Check if running as root
    if os.geteuid() != 0:
        print("[!] This script must be run as root (use sudo)", file=sys.stderr)
        sys.exit(1)

    # Parse command line arguments
    args = parse_args()

    # Handle --clear flag
    if args.clear:
        if clear_registration():
            sys.exit(0)
        else:
            sys.exit(1)

    # Get base64 string from argument or prompt
    if args.input:
        arg = args.input.strip()

        # Check if argument is a zip file
        if arg.endswith('.zip') and os.path.isfile(arg):
            base64_string = extract_base64_from_zip(arg)
            if not base64_string:
                print("[!] Failed to extract base64 from zip file")
                sys.exit(1)
        else:
            base64_string = arg
            print("[*] Using base64 string from command line argument")
    else:
        base64_string = get_base64_input()
        if not base64_string:
            sys.exit(1)

    # Create registrator instance
    registrator = LocalXDRRegistration(base64_string)

    # Step 1: Decode OVF string
    if not registrator.decode_ovf_string():
        sys.exit(1)

    # Step 2: Extract YAML files
    if not registrator.extract_yaml_files():
        sys.exit(1)

    # Step 3: Display configuration
    registrator.display_config_info()

    # Step 4: Check for existing registration
    if not registrator.check_existing_registration():
        print("[*] Registration cancelled")
        sys.exit(0)

    # Step 5: Check IPv4 forwarding
    registrator.check_ipv4_forwarding()

    # Step 6: Confirm before proceeding
    print("\nDo you want to proceed with registration? (yes/no)")
    confirm = input("> ").strip().lower()

    if confirm not in ["yes", "y"]:
        print("[*] Registration cancelled")
        sys.exit(0)

    # Step 7: Clean old certificates (forces regeneration with new credentials)
    registrator.clean_old_certificates()

    # Step 8: Write configuration files
    if not registrator.write_config_files():
        sys.exit(1)

    # Step 8: Run registration
    if not registrator.run_registration():
        print("\n[!] Registration failed. Check the logs above for errors.")
        sys.exit(1)

    # Step 9: Verify registration with MQTT heartbeat check
    if registrator.verify_registration():
        print("\n" + "=" * 70)
        print("[+] REGISTRATION SUCCESSFUL!")
        print("[+] MQTT heartbeat confirmed - appliance is connected to XDR cloud")
        print("=" * 70)
        print("\n[*] The appliance is now ready for use.")
        print("[*] You can configure targets in XDR Workflows to use this Remote.")
    else:
        print("\n" + "=" * 70)
        print("[!] REGISTRATION INCOMPLETE")
        print("[!] Containers started but MQTT connectivity could not be verified")
        print("=" * 70)
        print("\n[*] Troubleshooting steps:")
        print("    - Review the diagnostic commands above")
        print("    - Check network connectivity to MQTT broker on port 8883")
        print("    - Verify certificates in /etc/ao-remote/")
        print("    - Review syslog for error details")
        sys.exit(1)


if __name__ == "__main__":
    main()
