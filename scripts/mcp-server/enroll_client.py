#!/usr/bin/env python3
"""
RADKit Client Enrollment Script
v1.1 - 31-jan-2026: Added python radkit-client dependency check.

This script enrolls your RADKit client for certificate authentication.
"""

import argparse
import subprocess
import sys

# Check if radkit_client is installed, install if not
try:
    from radkit_client.sync import Client
except ImportError:
    print("radkit_client not found. Installing cisco_radkit_client==1.9.2...")
    try:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install",
            "cisco_radkit_client==1.9.2",
            "--break-system-packages"
        ])
        print("Installation complete.")
        print("")
        from radkit_client.sync import Client
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to install radkit_client: {e}")
        print("")
        print("Please install manually:")
        print("  python3 -m pip install cisco_radkit_client==1.9.2 --break-system-packages")
        print("")
        sys.exit(1)

# Hardcoded password for lab environment
RADKIT_PASSWORD = "0e52nsq5jf7f-bxq8whdi7dnT"


def main():
    parser = argparse.ArgumentParser(description="RADKit Client Enrollment")
    parser.add_argument("--email", "-e", help="Cisco email address for enrollment")
    args = parser.parse_args()

    # Determine if running interactively
    interactive = sys.stdin.isatty()

    print("=" * 70)
    print("RADKit Client Enrollment")
    print("=" * 70)
    print("")
    print("This script will enroll your RADKit client for certificate authentication.")
    print("")
    print("You will:")
    print("  1. Enter your Cisco email address")
    print("  2. Authenticate via SSO (copy URL to browser)")
    print("  3. Use the lab password for your private key")
    print("")
    print("=" * 70)
    print("")

    # Get email from argument or prompt
    if args.email:
        email = args.email.strip()
    elif interactive:
        email = input("Enter your Cisco email address: ").strip()
    else:
        print("Error: Email required. Use --email flag in non-interactive mode.")
        sys.exit(1)

    if not email:
        print("Error: Email cannot be empty")
        sys.exit(1)

    print("")
    print(f"Enrolling as: {email}")
    print("")
    print("=" * 70)
    print("IMPORTANT: OAuth Authentication Required")
    print("=" * 70)
    print("")
    print("A URL will appear below. You MUST:")
    print("  1. Copy the ENTIRE URL (starts with https://id.cisco.com/...)")
    print("  2. Paste it into your browser")
    print("  3. Complete the Cisco SSO login")
    print("  4. Return here after login completes")
    print("")
    print(f"Private key password (use this when prompted): {RADKIT_PASSWORD}")
    print("")

    if interactive:
        input("Press Enter to continue...")
    print("")

    try:
        with Client.create() as client:
            # Perform SSO login
            client.sso_login(domain="PROD", identity=email)

            print("")
            print("=" * 70)
            print("SSO authentication successful!")
            print("=" * 70)
            print("")
            print("Now enrolling client certificate...")
            print(f"When prompted for password, enter: {RADKIT_PASSWORD}")
            print("")

            # Enroll client
            client.enroll_client()

            print("")
            print("=" * 70)
            print("Enrollment Complete!")
            print("=" * 70)
            print("")
            print(f"Certificates saved to: ~/.radkit/identities/prod.radkit-cloud.cisco.com/{email}/")
            print("")
            print("You can now run: ./setup_mcp.sh")
            print("")

    except KeyboardInterrupt:
        print("")
        print("Enrollment cancelled by user")
        sys.exit(1)
    except Exception as e:
        print("")
        print(f"Error during enrollment: {e}")
        print("")
        print("If SSO failed, make sure you:")
        print("  1. Copied the FULL URL to your browser")
        print("  2. Completed the login successfully")
        print("  3. Have network access to id.cisco.com")
        print("")
        sys.exit(1)


if __name__ == "__main__":
    main()
