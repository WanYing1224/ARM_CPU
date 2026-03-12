import struct

def hex_to_int64(hex_str):
    # Strip whitespace/0x and ensure it is treated as a 64-bit value
    clean_str = hex_str.strip().lower().replace('0x', '')
    
    # PAD TO 16 CHARACTERS: This is the critical step for 64-bit signed values.
    # If the hex value starts with 'f', it's negative; pad with 'f'.
    # Otherwise, pad with '0'.
    if clean_str.startswith('f'):
        full_hex = clean_str.rjust(16, 'f')
    else:
        full_hex = clean_str.rjust(16, '0')
        
    val = int(full_hex, 16)
    
    # 64-bit Two's Complement check
    if val >= 0x8000000000000000:
        val -= (1 << 64)
    return val

def dump_memory(filename, start_addr=0, count=10):
    print(f"--- Memory Dump: {filename} ---")
    print(f"{'Address':<10} | {'Hex Value':<20} | {'Signed Integer'}")
    print("-" * 55)
    
    try:
        with open(filename, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
            for i in range(start_addr, min(start_addr + count, len(lines))):
                hex_val = lines[i]
                signed_int = hex_to_int64(hex_val)
                print(f"0x{i:02x}       | {hex_val:<20} | {signed_int}")
    except FileNotFoundError:
        print(f"Error: {filename} not found.")

if __name__ == "__main__":
    print("EXPECTED INITIAL: 323, 123, -455, 2, 98, 125, 10, 65, -56, 0")
    dump_memory("dmem_before.hex")

    print("\nEXPECTED SORTED: -455, -56, 0, 2, 10, 65, 98, 123, 125, 323")
    dump_memory("dmem_after.hex")