# Cisco ToolBox to OpenAI Tools Converter

This script converts Cisco Workflow ToolBox JSON exports into OpenAI Chat Completions API tool specifications. Once Cisco Workflows releases their API, this script will be deprecated in favor of natively obtaining the tool list via a workflow API call to the workflows list, but this is in place in case you want to add your own tools before the API is available.

## Usage

### Basic Usage

By default, the script looks for ToolBox files in `workflows/ai_agent/ToolBox*`:

```bash
python convert_toolbox_to_openai_tools.py --all
```

### Command Line Options

- `-i, --input FILE`: Path to ToolBox JSON file - **overrides default location** (default: `workflows/ai_agent/ToolBox*`)
- `-o, --output FILE`: Save output to file (default: stdout)
- `--all`: Auto-include all tools without prompting (Base Agent Tools always included)
- `--workflows-dir DIR`: Base workflows directory for finding subworkflows (default: `workflows/`)

### Overriding the ToolBox Workflow

You can override the default ToolBox location in several ways:

1. **Direct file path**:
   ```bash
   python convert_toolbox_to_openai_tools.py -i /path/to/custom/ToolBox.json --all
   ```

2. **Relative path**:
   ```bash
   python convert_toolbox_to_openai_tools.py -i ../other_project/ToolBox.json --all
   ```

3. **With custom subworkflow directory**:
   ```bash
   python convert_toolbox_to_openai_tools.py \
     -i custom_toolbox.json \
     --workflows-dir /path/to/subworkflows \
     --all
   ```

The script will:
- Use the exact file path if it exists
- Otherwise, treat it as a glob pattern
- Fall back to the default `workflows/ai_agent/ToolBox*` pattern if not specified

**Smart Workflows Directory Detection:**

When you provide a custom ToolBox path with `-i` and don't specify `--workflows-dir`, the script automatically detects the workflows directory based on the ToolBox location:

```bash
# From utils/src/ directory with relative path
python convert_toolbox_to_openai_tools.py \
  -i ../../workflows/ai_agent/ToolBox__xxx/definition_workflow_xxx.json \
  --all

# Output:
# Auto-detected workflows directory: /Users/.../workflows
```

This ensures subworkflows are found correctly regardless of where you run the script from.

### Examples

**Convert with all tools auto-included:**
```bash
python convert_toolbox_to_openai_tools.py --all
```

**Save output to file:**
```bash
python convert_toolbox_to_openai_tools.py --all -o tools_spec.json
```

**Use custom ToolBox file:**
```bash
python convert_toolbox_to_openai_tools.py -i path/to/custom_toolbox.json --all
```

**Interactive mode (prompts for each tool):**
```bash
python convert_toolbox_to_openai_tools.py
```

## How It Works

1. **Loads ToolBox JSON**: Finds and parses the main ToolBox workflow file
2. **Extracts Tools**: Identifies all condition branches representing tools
3. **Finds Subworkflows**: Searches for corresponding subworkflow JSON files
4. **Parses Parameters**: Extracts parameter definitions from subworkflows
5. **Converts Types**: Maps Cisco datatypes to OpenAI types
6. **Generates Spec**: Builds OpenAI-compatible function specifications

## Input Structure

The script expects:
- **ToolBox JSON**: Main workflow file with condition blocks
- **Subworkflow JSONs**: Individual tool definitions (optional, will prompt if missing)

### ToolBox Structure
```
workflows/
└── ai_agent/
    ├── ToolBox__definition_workflow_*/
    │   └── definition_workflow_*.json
    ├── ToolRADKITExecCommand__definition_workflow_*/
    │   └── definition_workflow_*.json
    └── ToolReadScratchpad__definition_workflow_*/
        └── definition_workflow_*.json
```

## Output Format

The script outputs JSON in OpenAI Chat Completions API format:

```json
[
  {
    "type": "function",
    "function": {
      "name": "exec_command",
      "description": "Executes a command to a device via RADKIT MCP Server",
      "parameters": {
        "type": "object",
        "properties": {
          "i_device_name": {
            "type": "string",
            "description": "RADKIT Device Name"
          },
          "i_command": {
            "type": "string",
            "description": "Command to send to device"
          }
        },
        "required": ["i_device_name", "i_command"]
      }
    }
  }
]
```

## Special Handling

### Base Agent Tools
Tools under the "Base Agent Tools" condition block are **always included** automatically, regardless of the `--all` flag.

### Missing Subworkflows
If a subworkflow JSON file is not found, the script will:
1. Prompt for tool description
2. Ask for number of parameters
3. For each parameter, prompt for:
   - Name
   - Description
   - Type (string/boolean/integer/number)
   - Required status
   - Enum values (optional)

### Type Mapping
Cisco datatypes are automatically converted:
- `datatype.string` → `"string"`
- `datatype.boolean` → `"boolean"`
- `datatype.integer` → `"integer"`
- `datatype.number` → `"number"`

## Notes

- The script skips "example" tools (tools without a `workflow_id`)
- Parameter names from Cisco workflows are preserved (e.g., `i_device_name`)
- All output is valid OpenAI Chat Completions API format
- The script can be run non-interactively with `--all` for automation

## Future Enhancements

This script is designed to be eventually converted to Go. The Python version serves as a prototype and reference implementation.
