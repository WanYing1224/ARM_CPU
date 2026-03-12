import re

def generate_coe(asm_file, coe_file):
    print(f"Processing {asm_file}...")
    try:
        with open(asm_file, 'r', encoding='utf-8', errors='ignore') as asm_f:
            lines = asm_f.readlines()
        
        instructions = []
        # Regex extracts just the 8-character hex machine code
        pattern = re.compile(r'^\s*[0-9a-fA-F]+:\s+([0-9a-fA-F]{8})')
        
        for line in lines:
            match = pattern.search(line)
            if match:
                instructions.append(match.group(1))
        
        if instructions:
            with open(coe_file, 'w') as coe_f:
                # Xilinx COE header
                coe_f.write("memory_initialization_radix=16;\n")
                coe_f.write("memory_initialization_vector=\n")
                
                # Write instructions separated by commas, ending with a semicolon
                coe_f.write(",\n".join(instructions))
                coe_f.write(";\n")
                
            print(f"Success! Generated {coe_file} with {len(instructions)} instructions.")
        else:
            print("Warning: No instructions found. Check your text file format.")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    # Ensure 'sort_disassembly.txt' is in the same folder
    generate_coe("sort_disassembly.txt", "imem.coe")
    