#!/bin/bash
# =========================================================================
# FIXED hw_test.sh
# =========================================================================

BITFILE="nf2_top.bit" 
PERL_SCRIPT="armcpu.pl"
INST_MEM="inst.mem"
DATA_MEM="data_init.hex"

# CORRECTED: DMEM index must match Verilog array size [0:255]
IMEM_BASE=0
DMEM_BASE=0 # Data Memory in your Verilog starts at 0 relative to its block

echo "==================================================="
echo " 1. Holding CPU Pipeline in Reset..."
echo "==================================================="
perl $PERL_SCRIPT reset 1

echo "==================================================="
echo " 2. Loading $INST_MEM into Instruction Memory..."
echo "==================================================="
ADDR=$IMEM_BASE
while IFS= read -r line || [ -n "$line" ]; do
    CLEAN_DATA=$(echo "$line" | tr -d '\r\n\t ,;')
    if [[ -n "$CLEAN_DATA" ]]; then
        ADDR_HEX=$(printf "%x" $ADDR)
        perl $PERL_SCRIPT write $ADDR_HEX $CLEAN_DATA
        ADDR=$((ADDR + 4))
    fi
done < "$INST_MEM"

# IMPORTANT: Your Verilog uses $readmemh("data_init.hex") inside the module. 
# However, if you want to overwrite it via PCIe during the script:
echo "==================================================="
echo " 3. Loading $DATA_MEM into Data Memory..."
echo "==================================================="
# Use a high offset or specific address range defined in your NetFPGA project 
# for Data Memory. If it shares the bus with IMEM, use a unique offset.
# For this lab, we'll assume DMEM is accessed at an offset known to armcpu.pl.
ADDR=1024 # Example: Placing Data Memory right after Instruction Memory
if [ -f "$DATA_MEM" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        CLEAN_DATA=$(echo "$line" | tr -d '\r\n\t ,;')
        if [[ -n "$CLEAN_DATA" ]]; then
            ADDR_HEX=$(printf "%x" $ADDR)
            perl $PERL_SCRIPT write $ADDR_HEX $CLEAN_DATA
            ADDR=$((ADDR + 4))
        fi
    done < "$DATA_MEM"
fi

echo "==================================================="
echo " 4. Releasing Reset (Executing Hardware Sort!)"
echo "==================================================="
perl $PERL_SCRIPT reset 0
sleep 2 

echo "==================================================="
echo " 5. CPU Hardware Status & Verification"
echo "==================================================="
perl $PERL_SCRIPT status

for i in {0..9}; do
    OFFSET=$((i * 4))
    # Match the loading ADDR from step 3
    TARGET_ADDR=$(printf "0x%x" $((1024 + OFFSET)))
    regwrite 0x2000204 $TARGET_ADDR
    DATA=$(regread 0x2000210)
    echo "DataMem[$TARGET_ADDR] = $DATA"
done
