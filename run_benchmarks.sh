#!/bin/bash
set -e
SUDO="echo 950715 | sudo -S"
WD=/home/yu/TieredVol
RUN_TS=$(date +%Y%m%d_%H%M%S)
mkdir -p $WD/benchmarks/run_${RUN_TS}

cd $WD

echo "============================================="
echo "  TieredVol vs LVM Benchmark Suite"
echo "  Run: ${RUN_TS}"
echo "============================================="
echo ""

# Clean up any leftover volumes
echo "=== Cleanup ==="
for vol in $($SUDO ./tiered_setup --list 2>/dev/null | grep "tv_test\|lv_test\|lv_stripe" | awk '{print $1}'); do
    $SUDO ./tiered_setup --destroy --name "$vol" 2>/dev/null || true
done
echo "Cleanup done."
echo ""

###############################################################################
# STEP 1: TieredVol 2-disk benchmarks (nvme0n1 + sdb/MX500)
###############################################################################
echo "============================================="
echo "  STEP 1: TieredVol 2-disk (NVMe+SATA)"
echo "============================================="

# T1: 2-disk 5GB Write
echo "[STEP 1.1/12] TieredVol 2-disk 5GB write — 5 runs"
$SUDO ./tiered_setup --create --name tv_test_2d \
    --disks nvme0n1:100,sdb:100 --scheduler 2>&1 | tee benchmarks/run_${RUN_TS}/setup_tv_2d.txt

for i in 1 2 3 4 5; do
    echo "--- T1 Run $i ---" >> benchmarks/run_${RUN_TS}/2disk_5gb_write_raw.txt
    $SUDO ./tiered_io --name tv_test_2d --bench --size 5GB 2>&1 | tee -a benchmarks/run_${RUN_TS}/2disk_5gb_write_raw.txt
    sleep 10
done
$SUDO ./tiered_setup --destroy --name tv_test_2d 2>&1 || true
sleep 5

# T2: 2-disk 5GB Read
echo "[STEP 1.2/12] TieredVol 2-disk 5GB read — 5 runs"
$SUDO ./tiered_setup --create --name tv_test_2d \
    --disks nvme0n1:100,sdb:100 --scheduler 2>&1 | tee benchmarks/run_${RUN_TS}/setup_tv_2d_read.txt

for i in 1 2 3 4 5; do
    echo "--- T2 Run $i ---" >> benchmarks/run_${RUN_TS}/2disk_5gb_read_raw.txt
    $SUDO ./tiered_io --name tv_test_2d --bench-read --size 5GB 2>&1 | tee -a benchmarks/run_${RUN_TS}/2disk_5gb_read_raw.txt
    sleep 10
done
$SUDO ./tiered_setup --destroy --name tv_test_2d 2>&1 || true
sleep 5

# T3: 2-disk 512MB Write
echo "[STEP 1.3/12] TieredVol 2-disk 512MB write — 5 runs"
$SUDO ./tiered_setup --create --name tv_test_2d \
    --disks nvme0n1:100,sdb:100 --scheduler 2>&1 | tee benchmarks/run_${RUN_TS}/setup_tv_2d_512.txt

for i in 1 2 3 4 5; do
    echo "--- T3 Run $i ---" >> benchmarks/run_${RUN_TS}/2disk_512mb_write_raw.txt
    $SUDO ./tiered_io --name tv_test_2d --bench --size 512MB 2>&1 | tee -a benchmarks/run_${RUN_TS}/2disk_512mb_write_raw.txt
    sleep 10
done
$SUDO ./tiered_setup --destroy --name tv_test_2d 2>&1 || true
sleep 5

###############################################################################
# STEP 2: TieredVol 3-disk benchmarks (nvme0n1 + sdb/MX500 + sdc/WD Blue)
###############################################################################
echo "============================================="
echo "  STEP 2: TieredVol 3-disk (NVMe+2×SATA)"
echo "============================================="

# T4: 3-disk 5GB Write
echo "[STEP 2.1/12] TieredVol 3-disk 5GB write — 5 runs"
$SUDO ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1 | tee benchmarks/run_${RUN_TS}/setup_tv_3d.txt

for i in 1 2 3 4 5; do
    echo "--- T4 Run $i ---" >> benchmarks/run_${RUN_TS}/3disk_5gb_write_raw.txt
    $SUDO ./tiered_io --name tv_test_3d --bench --size 5GB 2>&1 | tee -a benchmarks/run_${RUN_TS}/3disk_5gb_write_raw.txt
    sleep 10
done
$SUDO ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 5

# T5: 3-disk 5GB Read
echo "[STEP 2.2/12] TieredVol 3-disk 5GB read — 5 runs"
$SUDO ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1 | tee benchmarks/run_${RUN_TS}/setup_tv_3d_read.txt

for i in 1 2 3 4 5; do
    echo "--- T5 Run $i ---" >> benchmarks/run_${RUN_TS}/3disk_5gb_read_raw.txt
    $SUDO ./tiered_io --name tv_test_3d --bench-read --size 5GB 2>&1 | tee -a benchmarks/run_${RUN_TS}/3disk_5gb_read_raw.txt
    sleep 10
done
$SUDO ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 5

###############################################################################
# STEP 3: LVM Benchmarks (same disks via tv_lvm_vg)
###############################################################################
echo "============================================="
echo "  STEP 3: LVM Striped (same disk config)"
echo "============================================="

# L1: LVM 2-disk NVMe+SATA 5GB Write (nvme0n1 + sdb, stripe=256KB)
echo "[STEP 3.1/12] LVM 2-disk NVMe+SATA 5GB write — 5 runs"
$SUDO lvremove -f tv_lvm_vg/lvm_bench_2d 2>/dev/null || true
$SUDO lvcreate -L 100G -i 2 -I 256k -n lvm_bench_2d tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
LV2D=$($SUDO lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_2d 2>/dev/null | tr -d ' ')
echo "LV path: $LV2D"

for i in 1 2 3 4 5; do
    echo "--- L1 Run $i ---" >> benchmarks/run_${RUN_TS}/lvm_nvsata_2disk_5gb_write_raw.txt
    $SUDO ./tiered_io --path "$LV2D" --bench --size 5GB --raw 2>&1 | tee -a benchmarks/run_${RUN_TS}/lvm_nvsata_2disk_5gb_write_raw.txt
    sleep 10
done
$SUDO lvremove -f tv_lvm_vg/lvm_bench_2d 2>&1
sleep 5

# L2: LVM 2-disk NVMe+SATA 5GB Read
echo "[STEP 3.2/12] LVM 2-disk NVMe+SATA 5GB read — 5 runs"
$SUDO lvcreate -L 100G -i 2 -I 256k -n lvm_bench_2d tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
LV2D=$($SUDO lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_2d 2>/dev/null | tr -d ' ')

for i in 1 2 3 4 5; do
    echo "--- L2 Run $i ---" >> benchmarks/run_${RUN_TS}/lvm_nvsata_2disk_5gb_read_raw.txt
    $SUDO ./tiered_io --path "$LV2D" --bench-read --size 5GB --raw 2>&1 | tee -a benchmarks/run_${RUN_TS}/lvm_nvsata_2disk_5gb_read_raw.txt
    sleep 10
done
$SUDO lvremove -f tv_lvm_vg/lvm_bench_2d 2>&1
sleep 5

# L3: LVM 2-disk NVMe+SATA 512MB Write
echo "[STEP 3.3/12] LVM 2-disk NVMe+SATA 512MB write — 5 runs"
$SUDO lvcreate -L 100G -i 2 -I 256k -n lvm_bench_2d tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
LV2D=$($SUDO lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_2d 2>/dev/null | tr -d ' ')

for i in 1 2 3 4 5; do
    echo "--- L3 Run $i ---" >> benchmarks/run_${RUN_TS}/lvm_nvsata_2disk_512mb_write_raw.txt
    $SUDO ./tiered_io --path "$LV2D" --bench --size 512MB --raw 2>&1 | tee -a benchmarks/run_${RUN_TS}/lvm_nvsata_2disk_512mb_write_raw.txt
    sleep 10
done
$SUDO lvremove -f tv_lvm_vg/lvm_bench_2d 2>&1
sleep 5

# L4: LVM 3-disk NVMe+2×SATA 5GB Write (nvme0n1 + sdb + sdc)
echo "[STEP 3.4/12] LVM 3-disk NVMe+2×SATA 5GB write — 5 runs"
$SUDO lvremove -f tv_lvm_vg/lvm_bench_3d 2>/dev/null || true
$SUDO lvcreate -L 100G -i 3 -I 256k -n lvm_bench_3d tv_lvm_vg 2>&1
LV3D=$($SUDO lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_3d 2>/dev/null | tr -d ' ')
echo "LV path: $LV3D"

for i in 1 2 3 4 5; do
    echo "--- L4 Run $i ---" >> benchmarks/run_${RUN_TS}/lvm_nvsata_3disk_5gb_write_raw.txt
    $SUDO ./tiered_io --path "$LV3D" --bench --size 5GB --raw 2>&1 | tee -a benchmarks/run_${RUN_TS}/lvm_nvsata_3disk_5gb_write_raw.txt
    sleep 10
done
$SUDO lvremove -f tv_lvm_vg/lvm_bench_3d 2>&1
sleep 5

# L5: LVM 3-disk NVMe+2×SATA 5GB Read
echo "[STEP 3.5/12] LVM 3-disk NVMe+2×SATA 5GB read — 5 runs"
$SUDO lvcreate -L 100G -i 3 -I 256k -n lvm_bench_3d tv_lvm_vg 2>&1
LV3D=$($SUDO lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_3d 2>/dev/null | tr -d ' ')

for i in 1 2 3 4 5; do
    echo "--- L5 Run $i ---" >> benchmarks/run_${RUN_TS}/lvm_nvsata_3disk_5gb_read_raw.txt
    $SUDO ./tiered_io --path "$LV3D" --bench-read --size 5GB --raw 2>&1 | tee -a benchmarks/run_${RUN_TS}/lvm_nvsata_3disk_5gb_read_raw.txt
    sleep 10
done
$SUDO lvremove -f tv_lvm_vg/lvm_bench_3d 2>&1
sleep 5

###############################################################################
# STEP 4: LVM Stripe Size Sweep (2-disk NVMe+SATA, 3 runs each)
###############################################################################
echo "============================================="
echo "  STEP 4: LVM Stripe Size Sweep"
echo "============================================="

for STRIPE in 128 256 512 1024; do
    echo "[STEP 4] LVM stripe=${STRIPE}KB 5GB write — 3 runs"
    $SUDO lvremove -f tv_lvm_vg/lvm_stripe_${STRIPE} 2>/dev/null || true
    $SUDO lvcreate -L 100G -i 2 -I ${STRIPE}k -n lvm_stripe_${STRIPE} tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
    LVPATH=$($SUDO lvs --noheadings -o lv_path tv_lvm_vg/lvm_stripe_${STRIPE} 2>/dev/null | tr -d ' ')

    for i in 1 2 3; do
        echo "--- Run $i (stripe=${STRIPE}KB) ---" >> benchmarks/run_${RUN_TS}/lvm_stripesize_${STRIPE}kb_raw.txt
        $SUDO ./tiered_io --path "$LVPATH" --bench --size 5GB --raw 2>&1 | tee -a benchmarks/run_${RUN_TS}/lvm_stripesize_${STRIPE}kb_raw.txt
        sleep 10
    done
    $SUDO lvremove -f tv_lvm_vg/lvm_stripe_${STRIPE} 2>&1
done
sleep 5

###############################################################################
# STEP 5: TieredVol Chunk Size Sweep (2-disk NVMe+SATA, 3 runs each)
###############################################################################
echo "============================================="
echo "  STEP 5: TieredVol Chunk Size Sweep"
echo "============================================="

# Save original chunk size definition
ORIG_CHUNK=$(grep "TV_CHUNK_SIZE" src/tiered_types.h | head -1)

for CHUNK_KB in 256 512; do
    echo "[STEP 5] Rebuilding with TV_CHUNK_SIZE=${CHUNK_KB}KB"
    sed -i "s/#define TV_CHUNK_SIZE.*/#define TV_CHUNK_SIZE (${CHUNK_KB} * 1024)/" src/tiered_types.h
    make clean && make 2>&1 | tail -3

    $SUDO ./tiered_setup --create --name tv_chunk_${CHUNK_KB} \
        --disks nvme0n1:100,sdb:100 --scheduler 2>&1

    for i in 1 2 3; do
        echo "--- Run $i (chunk=${CHUNK_KB}KB) ---" >> benchmarks/run_${RUN_TS}/chunksize_${CHUNK_KB}kb_raw.txt
        $SUDO ./tiered_io --name tv_chunk_${CHUNK_KB} --bench --size 5GB 2>&1 | tee -a benchmarks/run_${RUN_TS}/chunksize_${CHUNK_KB}kb_raw.txt
        sleep 10
    done
    $SUDO ./tiered_setup --destroy --name tv_chunk_${CHUNK_KB} 2>&1 || true
    sleep 5
done

# Restore original chunk size
echo "Restoring default chunk size..."
make clean && make 2>&1 | tail -3
sleep 5

###############################################################################
# STEP 6: io_uring Metrics (3-disk)
###############################################################################
echo "============================================="
echo "  STEP 6: io_uring Metrics"
echo "============================================="

# I1: strace
echo "[STEP 6.1] strace io_uring_enter — 3-disk 5GB write"
$SUDO ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1
$SUDO strace -e trace=io_uring_enter -c \
    ./tiered_io --name tv_test_3d --bench --size 5GB 2>&1 | tee benchmarks/run_${RUN_TS}/uring_3disk_strace_count.txt
$SUDO ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 5

# I2: perf stat
echo "[STEP 6.2] perf stat — 3-disk 5GB write"
$SUDO ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1
$SUDO perf stat -e syscalls:sys_enter_io_uring_enter,syscalls:sys_exit_io_uring_enter \
    ./tiered_io --name tv_test_3d --bench --size 5GB 2>&1 | tee benchmarks/run_${RUN_TS}/uring_3disk_perf_stat.txt
$SUDO ./tiered_setup --destroy --name tv_test_3d 2>&1 || true

###############################################################################
# STEP 7: Copy raw output to benchmarks/
###############################################################################
echo "============================================="
echo "  STEP 7: Copying raw output"
echo "============================================="
cp benchmarks/run_${RUN_TS}/*.txt benchmarks/ 2>/dev/null || true
echo "Copied raw output to benchmarks/"
ls -la benchmarks/*.txt

###############################################################################
# STEP 8: Generate summary
###############################################################################
echo "============================================="
echo "  STEP 8: Generating summary"
echo "============================================="

cat > benchmarks/summary-v2.md << 'HEREDOC'
# Benchmark Summary v2 — B85 Platform (Fair Comparison)

## System
- CPU: Intel i5-4570
- RAM: DDR3 1600MHz
- NVMe: P3 Plus 1T (PCIe 2.0x4)
- SATA: MX500 500G + WD Blue NAND 250G
- OS: Lubuntu, Linux 6.x

## TieredVol Scheduler (Weighted Stripe)

| Scenario | Mean (MB/s) | StdDev | Runs |
|----------|------------|--------|------|
HEREDOC

# Parse TieredVol results
for f in 2disk_5gb_write 2disk_5gb_read 2disk_512mb_write 3disk_5gb_write 3disk_5gb_read; do
    if [ -f "benchmarks/${f}_raw.txt" ]; then
        MEAN=$(grep "Throughput:" benchmarks/${f}_raw.txt | awk '{print $2}' | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n}')
        STDDEV=$(grep "Throughput:" benchmarks/${f}_raw.txt | awk '{print $2}' | awk '{s+=$1; ss+=$1*$1; n++} END {if(n>1) printf "%.1f", sqrt((ss-s*s/n)/(n-1)); else print "0.0"}')
        RUNS=$(grep -c "Throughput:" benchmarks/${f}_raw.txt)
        echo "| ${f} | ${MEAN} | ${STDDEV} | ${RUNS} |" >> benchmarks/summary-v2.md
    fi
done

cat >> benchmarks/summary-v2.md << 'HEREDOC'

## LVM Striped — Same Disk Configuration (NVMe+SATA)

| Scenario | Mean (MB/s) | StdDev | Runs |
|----------|------------|--------|------|
HEREDOC

for f in lvm_nvsata_2disk_5gb_write lvm_nvsata_2disk_5gb_read lvm_nvsata_2disk_512mb_write lvm_nvsata_3disk_5gb_write lvm_nvsata_3disk_5gb_read; do
    if [ -f "benchmarks/${f}_raw.txt" ]; then
        MEAN=$(grep "Throughput:" benchmarks/${f}_raw.txt | awk '{print $2}' | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n}')
        STDDEV=$(grep "Throughput:" benchmarks/${f}_raw.txt | awk '{print $2}' | awk '{s+=$1; ss+=$1*$1; n++} END {if(n>1) printf "%.1f", sqrt((ss-s*s/n)/(n-1)); else print "0.0"}')
        RUNS=$(grep -c "Throughput:" benchmarks/${f}_raw.txt)
        echo "| ${f} | ${MEAN} | ${STDDEV} | ${RUNS} |" >> benchmarks/summary-v2.md
    fi
done

cat >> benchmarks/summary-v2.md << 'HEREDOC'

## LVM Stripe Size Sweep (2-disk NVMe+SATA, 5GB write)

| Stripe Size | Mean (MB/s) | Runs |
|-------------|------------|------|
HEREDOC

for STRIPE in 128 256 512 1024; do
    if [ -f "benchmarks/lvm_stripesize_${STRIPE}kb_raw.txt" ]; then
        MEAN=$(grep "Throughput:" benchmarks/lvm_stripesize_${STRIPE}kb_raw.txt | awk '{print $2}' | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n}')
        RUNS=$(grep -c "Throughput:" benchmarks/lvm_stripesize_${STRIPE}kb_raw.txt)
        echo "| ${STRIPE} KB | ${MEAN} | ${RUNS} |" >> benchmarks/summary-v2.md
    fi
done

cat >> benchmarks/summary-v2.md << 'HEREDOC'

## TieredVol Chunk Size Sweep (2-disk NVMe+SATA, 5GB write)

| Chunk Size | Mean (MB/s) | Runs |
|------------|------------|------|
HEREDOC

for CHUNK in 256 512 1024; do
    if [ -f "benchmarks/chunksize_${CHUNK}kb_raw.txt" ]; then
        MEAN=$(grep "Throughput:" benchmarks/chunksize_${CHUNK}kb_raw.txt | awk '{print $2}' | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n}')
        RUNS=$(grep -c "Throughput:" benchmarks/chunksize_${CHUNK}kb_raw.txt)
        echo "| ${CHUNK} KB | ${MEAN} | ${RUNS} |" >> benchmarks/summary-v2.md
    fi
done

echo "" >> benchmarks/summary-v2.md
echo "Run directory: benchmarks/run_${RUN_TS}" >> benchmarks/summary-v2.md
echo "Generated: $(date)" >> benchmarks/summary-v2.md

echo ""
echo "============================================="
echo "  FAIR COMPARISON: TieredVol vs LVM"
echo "  (Same disks, same carve sizes, O_DIRECT)"
echo "============================================="
echo ""
printf "  %-45s %12s %12s\n" "Scenario" "TieredVol" "LVM"
printf "  %-45s %12s %12s\n" "---------------------------------------------" "----------" "----------"

# 2-disk write
TV=$(grep "2disk_5gb_write" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
LV=$(grep "lvm_nvsata_2disk_5gb_write" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
printf "  %-45s %12s %12s\n" "2-disk 5GB write (NVMe+SATA)" "$TV" "$LV"

# 2-disk read
TV=$(grep "2disk_5gb_read" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
LV=$(grep "lvm_nvsata_2disk_5gb_read" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
printf "  %-45s %12s %12s\n" "2-disk 5GB read (NVMe+SATA)" "$TV" "$LV"

# 2-disk 512MB write
TV=$(grep "2disk_512mb_write" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
LV=$(grep "lvm_nvsata_2disk_512mb_write" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
printf "  %-45s %12s %12s\n" "2-disk 512MB write (NVMe+SATA)" "$TV" "$LV"

# 3-disk write
TV=$(grep "3disk_5gb_write" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
LV=$(grep "lvm_nvsata_3disk_5gb_write" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
printf "  %-45s %12s %12s\n" "3-disk 5GB write (NVMe+2xSATA)" "$TV" "$LV"

# 3-disk read
TV=$(grep "3disk_5gb_read" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
LV=$(grep "lvm_nvsata_3disk_5gb_read" benchmarks/summary-v2.md | head -1 | awk -F'|' '{print $3}')
printf "  %-45s %12s %12s\n" "3-disk 5GB read (NVMe+2xSATA)" "$TV" "$LV"

echo ""
echo "============================================="

echo ""
echo "=== ALL BENCHMARKS COMPLETE ==="
echo "Run timestamp: ${RUN_TS}"
