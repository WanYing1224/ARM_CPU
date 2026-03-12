# This is a python file for generating coe file for imem and dmem. 

import sys
import os

input_file = "./coe_file/sort.bin"
output_file = "./coe_file/sort.coe"

if not os.path.exists(input_file):
    print(f"Error: Could not find {input_file}")
    sys.exit(1)

with open(input_file, "rb") as f:
    bindata = f.read()

with open(output_file, "w") as f:
    # Write the required Xilinx header
    f.write("memory_initialization_radix=16;\n")
    f.write("memory_initialization_vector=\n")
    
    words = []
    for i in range(0, len(bindata), 4):
        chunk = bindata[i:i+4]

        chunk += b'\x00' * (4 - len(chunk)) 
        
        word_hex = f"{chunk[3]:02x}{chunk[2]:02x}{chunk[1]:02x}{chunk[0]:02x}"
        words.append(word_hex)
        
    f.write(",\n".join(words))
    f.write(";\n")

print(f"Successfully generated {output_file}!")
