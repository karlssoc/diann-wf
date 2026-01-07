# Test Data Generation

This directory contains tools to create minimal test data from full mzML
files while maintaining DIA-NN compatibility.

## Current Status

**Source files:**

-   `CK_M2512_002.raw`
-   `CK_M2512_003.raw`
-   `CK_M2512_004.raw`

## Quick Start

### Step 1: Generate minimal mzML files

```         
"C:\Users\admin\AppData\Local\Apps\ProteoWizard 3.0.24124.ba8a4fd 64-bit\msconvert.exe" --zlib --32 --filter "peakPicking true 1-" --filter "zeroSamples removeExtra"  --filter "threshold count 35 most-intense"  "E:\CK_M2512_004.raw" "E:\CK_M2512_003.raw"  "E:\CK_M2512_002.raw"
```

### Step 2: Convert to dia with DIANN 2.3.1

**Output files:**

-   `generate_example_data/CK_M2512_002.dia`
-   `generate_example_data/CK_M2512_003.dia`
-   `generate_example_data/CK_M2512_004.dia`

### Step 3: Test .dia files

**DIANN output:** 

-   `generate_example_data/diann`