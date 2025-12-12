#!/usr/bin/env python3
"""
Convert Cisco Workflow ToolBox JSON to OpenAI Chat Completions API Tool Specifications

This script parses Cisco Workflow exports (ToolBox format) and converts them to
OpenAI-compatible function calling tool specifications.
"""

import argparse
import json
import glob
import os
import sys
from typing import Optional, Dict, List, Any
from pathlib import Path


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Convert Cisco ToolBox workflows to OpenAI tool specifications",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use default ToolBox location
  %(prog)s --all

  # Override with custom ToolBox file
  %(prog)s -i path/to/custom_toolbox.json --all

  # Save output to file
  %(prog)s --all -o tools_spec.json

  # Use custom workflows directory for subworkflows
  %(prog)s -i custom_toolbox.json --workflows-dir /path/to/workflows --all
        """
    )
    parser.add_argument(
        "-i", "--input",
        help="Path to ToolBox JSON file (overrides default: workflows/ai_agent/ToolBox*)",
        default=None,
        metavar="FILE"
    )
    parser.add_argument(
        "-o", "--output",
        help="Output file path (default: stdout)",
        default=None,
        metavar="FILE"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Auto-include all tools without prompting (Base Agent Tools always included)"
    )
    parser.add_argument(
        "--workflows-dir",
        help="Base workflows directory for finding subworkflows (default: workflows/)",
        default="workflows/",
        metavar="DIR"
    )
    return parser.parse_args()


def find_toolbox_file(pattern: Optional[str] = None) -> str:
    """Find the ToolBox JSON file using glob pattern or direct path.

    Args:
        pattern: Either a direct file path or glob pattern.
                 If None, uses default: workflows/ai_agent/ToolBox*/definition_workflow_*.json

    Returns:
        Path to the ToolBox JSON file
    """
    # If pattern is a direct file path that exists, use it
    if pattern and os.path.exists(pattern):
        if os.path.isfile(pattern):
            return pattern
        else:
            print(f"Error: {pattern} is not a file", file=sys.stderr)
            sys.exit(1)

    # Use pattern as glob or fall back to default
    search_pattern = pattern or "workflows/ai_agent/ToolBox*/definition_workflow_*.json"
    matches = glob.glob(search_pattern)

    if not matches:
        print(f"Error: No ToolBox file found matching pattern: {search_pattern}", file=sys.stderr)
        print(f"Hint: Use -i to specify a custom ToolBox file path", file=sys.stderr)
        sys.exit(1)

    if len(matches) > 1:
        print(f"Warning: Multiple ToolBox files found. Using: {matches[0]}", file=sys.stderr)

    return matches[0]


def load_json(path: str) -> Dict[str, Any]:
    """Load and parse JSON file."""
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading JSON file {path}: {e}", file=sys.stderr)
        sys.exit(1)


def convert_cisco_type_to_openai(cisco_type: str) -> str:
    """Convert Cisco datatype to OpenAI type."""
    type_mapping = {
        "datatype.string": "string",
        "datatype.boolean": "boolean",
        "datatype.integer": "integer",
        "datatype.number": "number",
    }
    return type_mapping.get(cisco_type, "string")


def find_subworkflow_file(workflow_id: str, base_dir: str) -> Optional[str]:
    """Find subworkflow JSON file by workflow ID."""
    pattern = f"{base_dir}/**/*__{workflow_id}/{workflow_id}.json"
    matches = glob.glob(pattern, recursive=True)
    return matches[0] if matches else None


def parse_subworkflow(subworkflow_json: Dict[str, Any]) -> Dict[str, Any]:
    """Parse subworkflow JSON to extract description and parameters."""
    workflow = subworkflow_json.get("workflow", {})
    properties = workflow.get("properties", {})

    result = {
        "description": properties.get("description", ""),
        "parameters": []
    }

    # Extract input variables
    variables = workflow.get("variables", [])
    for var in variables:
        var_props = var.get("properties", {})
        if var_props.get("scope") == "input":
            param = {
                "name": var_props.get("name", ""),
                "description": var_props.get("description", ""),
                "type": convert_cisco_type_to_openai(var_props.get("type", "datatype.string")),
                "required": var_props.get("is_required", False)
            }
            result["parameters"].append(param)

    return result


def extract_tools_from_toolbox(toolbox_json: Dict[str, Any], workflows_dir: str) -> List[Dict[str, Any]]:
    """Extract all tools from ToolBox JSON."""
    workflow = toolbox_json.get("workflow", {})
    actions = workflow.get("actions", [])
    tools = []

    for action in actions:
        # Check if this is a Condition Block
        if action.get("type") != "logic.if_else":
            continue

        block_name = action.get("properties", {}).get("display_name", "")
        is_base_tool = "Base Agent Tools" in block_name

        blocks = action.get("blocks", [])
        for branch in blocks:
            # Check if this is a Condition Branch
            if branch.get("type") != "logic.condition_block":
                continue

            condition = branch.get("properties", {}).get("condition", {})
            function_name = condition.get("right_operand", "")
            display_name = branch.get("properties", {}).get("display_name", "")

            # Skip if no function name
            if not function_name:
                continue

            # Find subworkflow in branch actions
            branch_actions = branch.get("actions", [])
            workflow_id = None
            workflow_name = None
            subworkflow_desc = None

            for branch_action in branch_actions:
                if branch_action.get("type") == "workflow.sub_workflow":
                    props = branch_action.get("properties", {})
                    workflow_id = props.get("workflow_id")
                    workflow_name = props.get("workflow_name")
                    subworkflow_desc = props.get("description")
                    break

            tool = {
                "function_name": function_name,
                "display_name": display_name,
                "parent_block": block_name,
                "is_base_tool": is_base_tool,
                "workflow_id": workflow_id,
                "workflow_name": workflow_name,
                "description": subworkflow_desc or "",
                "parameters": []
            }

            # Try to find and parse subworkflow
            if workflow_id:
                subworkflow_path = find_subworkflow_file(workflow_id, workflows_dir)
                if subworkflow_path:
                    subworkflow_json = load_json(subworkflow_path)
                    parsed = parse_subworkflow(subworkflow_json)
                    tool["description"] = parsed["description"] or tool["description"]
                    tool["parameters"] = parsed["parameters"]

            tools.append(tool)

    return tools


def prompt_for_tool_inclusion(tool: Dict[str, Any], auto_include: bool) -> bool:
    """Prompt user whether to include a tool."""
    if tool["is_base_tool"]:
        return True

    if auto_include:
        return True

    while True:
        response = input(f"\nInclude tool '{tool['display_name']}' ({tool['function_name']})? (y/n): ").strip().lower()
        if response in ['y', 'yes']:
            return True
        elif response in ['n', 'no']:
            return False
        else:
            print("Please enter 'y' or 'n'")


def prompt_for_parameter_details(tool_name: str) -> List[Dict[str, Any]]:
    """Prompt user for parameter details when subworkflow is missing."""
    print(f"\nSubworkflow not found for tool: {tool_name}")
    print("Please provide parameter information manually.")

    while True:
        try:
            num_params = int(input("Number of parameters: "))
            break
        except ValueError:
            print("Please enter a valid number")

    parameters = []
    for i in range(num_params):
        print(f"\nParameter {i+1}:")
        name = input("  Name: ").strip()
        description = input("  Description: ").strip()

        while True:
            param_type = input("  Type (string/boolean/integer/number) [string]: ").strip().lower()
            if not param_type:
                param_type = "string"
            if param_type in ["string", "boolean", "integer", "number"]:
                break
            print("  Invalid type. Please enter: string, boolean, integer, or number")

        required = input("  Required? (y/n) [n]: ").strip().lower() in ['y', 'yes']

        enum_values = input("  Enum values (comma-separated, or press Enter to skip): ").strip()

        param = {
            "name": name,
            "description": description,
            "type": param_type,
            "required": required
        }

        if enum_values:
            param["enum"] = [v.strip() for v in enum_values.split(",")]

        parameters.append(param)

    return parameters


def prompt_for_description(tool_name: str) -> str:
    """Prompt user for tool description when subworkflow is missing."""
    return input(f"Description for tool '{tool_name}': ").strip()


def build_openai_function(tool: Dict[str, Any]) -> Dict[str, Any]:
    """Build OpenAI function specification from tool."""
    properties = {}
    required = []

    for param in tool["parameters"]:
        prop = {
            "type": param["type"],
            "description": param["description"]
        }

        if "enum" in param:
            prop["enum"] = param["enum"]

        properties[param["name"]] = prop

        if param["required"]:
            required.append(param["name"])

    function_spec = {
        "type": "function",
        "function": {
            "name": tool["function_name"],
            "description": tool["description"],
            "parameters": {
                "type": "object",
                "properties": properties
            }
        }
    }

    if required:
        function_spec["function"]["parameters"]["required"] = required

    return function_spec


def main():
    """Main entry point."""
    args = parse_args()

    # Find and load ToolBox JSON
    toolbox_path = find_toolbox_file(args.input)
    print(f"Loading ToolBox from: {toolbox_path}", file=sys.stderr)
    toolbox_json = load_json(toolbox_path)

    # Determine workflows directory
    # If user specified a custom ToolBox path and didn't override workflows_dir,
    # derive workflows_dir from the ToolBox location
    workflows_dir = args.workflows_dir
    if args.input and workflows_dir == "workflows/":
        # User provided custom input but didn't override workflows_dir
        # Derive workflows_dir from ToolBox location
        toolbox_dir = os.path.dirname(os.path.abspath(toolbox_path))
        # Go up to parent directory (from ToolBox__xxx/ to ai_agent/ or similar)
        parent_dir = os.path.dirname(toolbox_dir)
        # Use parent as workflows base, or go up one more level if needed
        if os.path.basename(parent_dir) in ['ai_agent', 'ai', 'mcp']:
            workflows_dir = os.path.dirname(parent_dir)
        else:
            workflows_dir = parent_dir
        print(f"Auto-detected workflows directory: {workflows_dir}", file=sys.stderr)

    # Extract tools
    print(f"Extracting tools...", file=sys.stderr)
    tools = extract_tools_from_toolbox(toolbox_json, workflows_dir)
    print(f"Found {len(tools)} tools", file=sys.stderr)

    # Process tools
    selected_tools = []
    for tool in tools:
        # Skip tools without workflow_id (example tools)
        if not tool["workflow_id"]:
            print(f"Skipping example tool: {tool['display_name']} (no workflow_id)", file=sys.stderr)
            continue

        # Check if tool should be included
        if not prompt_for_tool_inclusion(tool, args.all):
            print(f"Skipping tool: {tool['display_name']}", file=sys.stderr)
            continue

        # If no parameters were found from subworkflow, prompt user
        if not tool["parameters"]:
            print(f"\nWarning: No parameters found for {tool['display_name']}", file=sys.stderr)
            try:
                tool["parameters"] = prompt_for_parameter_details(tool["function_name"])
            except (EOFError, KeyboardInterrupt):
                print(f"\nSkipping tool {tool['display_name']} due to user interrupt", file=sys.stderr)
                continue

        # If no description, prompt user
        if not tool["description"]:
            try:
                tool["description"] = prompt_for_description(tool["function_name"])
            except (EOFError, KeyboardInterrupt):
                print(f"\nUsing default description for {tool['display_name']}", file=sys.stderr)
                tool["description"] = f"Tool: {tool['display_name']}"

        selected_tools.append(tool)

    # Build OpenAI specifications
    openai_specs = []
    for tool in selected_tools:
        spec = build_openai_function(tool)
        openai_specs.append(spec)

    # Output
    output_json = json.dumps(openai_specs, indent=2)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(output_json)
        print(f"\nTool specifications written to: {args.output}", file=sys.stderr)

    print(output_json)


if __name__ == "__main__":
    main()
