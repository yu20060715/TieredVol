#!/bin/bash
set -ex
WD=/home/yu/TieredVol
cd $WD
RUN_TS=$(date +%Y%m%d_%H%M%S)
mkdir -p $WD/benchmarks/run_${RUN_TS}
RDIR="benchmarks/run_${RUN_TS}"

echo "============================================="
echo "  TieredVol vs LVM Benchmark Suite v2"
echo "  Run: ${RUN_TS}"
echo "  Disk map: nvme0n1=NVMe, sdb=MX500, sdc=WDBlue"
echo "============================================="

###############################################################################
# STEP 1: TieredVol 2-disk (nvme0n1 + sdb)
###############################################################################
echo ""
echo "============================================="
echo "  STEP 1: TieredVol 2-disk (NVMe+SATA)"
echo "============================================="

# T1: 2-disk 5GB Write
echo "[STEP 1.1] TieredVol 2-disk 5GB write — 5 runs"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_2d \
    --disks nvme0n1:100,sdb:100 --scheduler 2>&1 | tee $RDIR/setup_tv_2d.txt

for i in 1 2 3 4 5; do
    echo "--- T1 Run $i ---" >> $RDIR/2disk_5gb_write_raw.txt
    echo 950715 | sudo -S ./tiered_io --name tv_test_2d --bench --size 5GB 2>&1 | tee -a $RDIR/2disk_5gb_write_raw.txt
    sleep 10
done
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_2d 2>&1 || true
sleep 10

# T2: 2-disk 5GB Read
echo "[STEP 1.2] TieredVol 2-disk 5GB read — 5 runs"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_2d \
    --disks nvme0n1:100,sdb:100 --scheduler 2>&1 | tee $RDIR/setup_tv_2d_read.txt

for i in 1 2 3 4 5; do
    echo "--- T2 Run $i ---" >> $RDIR/2disk_5gb_read_raw.txt
    echo 950715 | sudo -S ./tiered_io --name tv_test_2d --bench-read --size 5GB 2>&1 | tee -a $RDIR/2disk_5gb_read_raw.txt
    sleep 10
done
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_2d 2>&1 || true
sleep 10

# T3: 2-disk 512MB Write
echo "[STEP 1.3] TieredVol 2-disk 512MB write — 5 runs"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_2d \
    --disks nvme0n1:100,sdb:100 --scheduler 2>&1 | tee $RDIR/setup_tv_2d_512.txt

for i in 1 2 3 4 5; do
    echo "--- T3 Run $i ---" >> $RDIR/2disk_512mb_write_raw.txt
    echo 950715 | sudo -S ./tiered_io --name tv_test_2d --bench --size 512MB 2>&1 | tee -a $RDIR/2disk_512mb_write_raw.txt
    sleep 10
done
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_2d 2>&1 || true
sleep 10

###############################################################################
# STEP 2: TieredVol 3-disk (nvme0n1 + sdb + sdc)
###############################################################################
echo ""
echo "============================================="
echo "  STEP 2: TieredVol 3-disk (NVMe+2×SATA)"
echo "============================================="

# T4: 3-disk 5GB Write
echo "[STEP 2.1] TieredVol 3-disk 5GB write — 5 runs"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1 | tee $RDIR/setup_tv_3d.txt

for i in 1 2 3 4 5; do
    echo "--- T4 Run $i ---" >> $RDIR/3disk_5gb_write_raw.txt
    echo 950715 | sudo -S ./tiered_io --name tv_test_3d --bench --size 5GB 2>&1 | tee -a $RDIR/3disk_5gb_write_raw.txt
    sleep 10
done
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 10

# T5: 3-disk 5GB Read
echo "[STEP 2.2] TieredVol 3-disk 5GB read — 5 runs"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1 | tee $RDIR/setup_tv_3d_read.txt

for i in 1 2 3 4 5; do
    echo "--- T5 Run $i ---" >> $RDIR/3disk_5gb_read_raw.txt
    echo 950715 | sudo -S ./tiered_io --name tv_test_3d --bench-read --size 5GB 2>&1 | tee -a $RDIR/3disk_5gb_read_raw.txt
    sleep 10
done
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 10

###############################################################################
# STEP 3: LVM Benchmarks (same disks via tv_lvm_vg)
###############################################################################
echo ""
echo "============================================="
echo "  STEP 3: LVM Striped (same disk config)"
echo "============================================="

# L1: LVM 2-disk NVMe+SATA 5GB Write
echo "[STEP 3.1] LVM 2-disk NVMe+SATA 5GB write — 5 runs"
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_2d 2>/dev/null || true
echo 950715 | sudo -S lvcreate -L 100G -i 2 -I 256k -n lvm_bench_2d tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
LV2D=$(echo 950715 | sudo -S lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_2d 2>&1 | tr -d ' ')
echo "LV path: $LV2D"

for i in 1 2 3 4 5; do
    echo "--- L1 Run $i ---" >> $RDIR/lvm_nvsata_2disk_5gb_write_raw.txt
    echo 950715 | sudo -S ./tiered_io --path "$LV2D" --bench --size 5GB --raw 2>&1 | tee -a $RDIR/lvm_nvsata_2disk_5gb_write_raw.txt
    sleep 10
done
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_2d 2>&1
sleep 10

# L2: LVM 2-disk NVMe+SATA 5GB Read
echo "[STEP 3.2] LVM 2-disk NVMe+SATA 5GB read — 5 runs"
echo 950715 | sudo -S lvcreate -L 100G -i 2 -I 256k -n lvm_bench_2d tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
LV2D=$(echo 950715 | sudo -S lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_2d 2>&1 | tr -d ' ')
echo "LV path: $LV2D"

for i in 1 2 3 4 5; do
    echo "--- L2 Run $i ---" >> $RDIR/lvm_nvsata_2disk_5gb_read_raw.txt
    echo 950715 | sudo -S ./tiered_io --path "$LV2D" --bench-read --size 5GB --raw 2>&1 | tee -a $RDIR/lvm_nvsata_2disk_5gb_read_raw.txt
    sleep 10
done
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_2d 2>&1
sleep 10

# L3: LVM 2-disk NVMe+SATA 512MB Write
echo "[STEP 3.3] LVM 2-disk NVMe+SATA 512MB write — 5 runs"
echo 950715 | sudo -S lvcreate -L 100G -i 2 -I 256k -n lvm_bench_2d tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
LV2D=$(echo 950715 | sudo -S lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_2d 2>&1 | tr -d ' ')
echo "LV path: $LV2D"

for i in 1 2 3 4 5; do
    echo "--- L3 Run $i ---" >> $RDIR/lvm_nvsata_2disk_512mb_write_raw.txt
    echo 950715 | sudo -S ./tiered_io --path "$LV2D" --bench --size 512MB --raw 2>&1 | tee -a $RDIR/lvm_nvsata_2disk_512mb_write_raw.txt
    sleep 10
done
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_2d 2>&1
sleep 10

# L4: LVM 3-disk NVMe+2×SATA 5GB Write
echo "[STEP 3.4] LVM 3-disk NVMe+2×SATA 5GB write — 5 runs"
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_3d 2>/dev/null || true
echo 950715 | sudo -S lvcreate -L 100G -i 3 -I 256k -n lvm_bench_3d tv_lvm_vg 2>&1
LV3D=$(echo 950715 | sudo -S lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_3d 2>&1 | tr -d ' ')
echo "LV path: $LV3D"

for i in 1 2 3 4 5; do
    echo "--- L4 Run $i ---" >> $RDIR/lvm_nvsata_3disk_5gb_write_raw.txt
    echo 950715 | sudo -S ./tiered_io --path "$LV3D" --bench --size 5GB --raw 2>&1 | tee -a $RDIR/lvm_nvsata_3disk_5gb_write_raw.txt
    sleep 10
done
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_3d 2>&1
sleep 10

# L5: LVM 3-disk NVMe+2×SATA 5GB Read
echo "[STEP 3.5] LVM 3-disk NVMe+2×SATA 5GB read — 5 runs"
echo 950715 | sudo -S lvcreate -L 100G -i 3 -I 256k -n lvm_bench_3d tv_lvm_vg 2>&1
LV3D=$(echo 950715 | sudo -S lvs --noheadings -o lv_path tv_lvm_vg/lvm_bench_3d 2>&1 | tr -d ' ')
echo "LV path: $LV3D"

for i in 1 2 3 4 5; do
    echo "--- L5 Run $i ---" >> $RDIR/lvm_nvsata_3disk_5gb_read_raw.txt
    echo 950715 | sudo -S ./tiered_io --path "$LV3D" --bench-read --size 5GB --raw 2>&1 | tee -a $RDIR/lvm_nvsata_3disk_5gb_read_raw.txt
    sleep 10
done
echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_bench_3d 2>&1
sleep 10

###############################################################################
# STEP 4: LVM Stripe Size Sweep (2-disk NVMe+SATA, 3 runs)
###############################################################################
echo ""
echo "============================================="
echo "  STEP 4: LVM Stripe Size Sweep"
echo "============================================="

for STRIPE in 128 256 512 1024; do
    echo "[STEP 4] LVM stripe=${STRIPE}KB 5GB write — 3 runs"
    echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_stripe_${STRIPE} 2>/dev/null || true
    echo 950715 | sudo -S lvcreate -L 100G -i 2 -I ${STRIPE}k -n lvm_stripe_${STRIPE} tv_lvm_vg /dev/nvme0n1 /dev/sdb 2>&1
    LVPATH=$(echo 950715 | sudo -S lvs --noheadings -o lv_path tv_lvm_vg/lvm_stripe_${STRIPE} 2>&1 | tr -d ' ')
    echo "LV path: $LVPATH"

    for i in 1 2 3; do
        echo "--- Run $i (stripe=${STRIPE}KB) ---" >> $RDIR/lvm_stripesize_${STRIPE}kb_raw.txt
        echo 950715 | sudo -S ./tiered_io --path "$LVPATH" --bench --size 5GB --raw 2>&1 | tee -a $RDIR/lvm_stripesize_${STRIPE}kb_raw.txt
        sleep 10
    done
    echo 950715 | sudo -S lvremove -f tv_lvm_vg/lvm_stripe_${STRIPE} 2>&1
    sleep 10
done

###############################################################################
# STEP 5: TieredVol Chunk Size Sweep (2-disk, 3 runs)
###############################################################################
echo ""
echo "============================================="
echo "  STEP 5: TieredVol Chunk Size Sweep"
echo "============================================="

for CHUNK_KB in 256 512; do
    echo "[STEP 5] Rebuilding with TV_CHUNK_SIZE=${CHUNK_KB}KB"
    sed -i "s/#define TV_CHUNK_SIZE.*/#define TV_CHUNK_SIZE (${CHUNK_KB} * 1024)/" src/tiered_types.h
    make clean && make 2>&1 | tail -3

    echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_chunk_${CHUNK_KB} \
        --disks nvme0n1:100,sdb:100 --scheduler 2>&1

    for i in 1 2 3; do
        echo "--- Run $i (chunk=${CHUNK_KB}KB) ---" >> $RDIR/chunksize_${CHUNK_KB}kb_raw.txt
        echo 950715 | sudo -S ./tiered_io --name tv_chunk_${CHUNK_KB} --bench --size 5GB 2>&1 | tee -a $RDIR/chunksize_${CHUNK_KB}kb_raw.txt
        sleep 10
    done
    echo 950715 | sudo -S ./tiered_setup --destroy --name tv_chunk_${CHUNK_KB} 2>&1 || true
    sleep 10
done

# Restore default chunk size (1MB)
echo "Restoring default chunk size..."
sed -i "s/#define TV_CHUNK_SIZE.*/#define TV_CHUNK_SIZE (1 * 1024 * 1024)/" src/tiered_types.h
make clean && make 2>&1 | tail -3
sleep 5

###############################################################################
# STEP 6: io_uring Metrics (3-disk)
###############################################################################
echo ""
echo "============================================="
echo "  STEP 6: io_uring Metrics"
echo "============================================="

# I1: strace
echo "[STEP 6.1] strace io_uring_enter — 3-disk 5GB write"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1
echo 950715 | sudo -S strace -e trace=io_uring_enter -c \
    ./tiered_io --name tv_test_3d --bench --size 5GB 2>&1 | tee $RDIR/uring_3disk_strace_count.txt
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 10

# I2: perf stat
echo "[STEP 6.2] perf stat — 3-disk 5GB write"
echo "YES" | echo 950715 | sudo -S ./tiered_setup --create --name tv_test_3d \
    --disks nvme0n1:100,sdb:100,sdc:100 --scheduler 2>&1
echo 950715 | sudo -S perf stat -e syscalls:sys_enter_io_uring_enter,syscalls:sys_exit_io_uring_enter \
    ./tiered_io --name tv_test_3d --bench --size 5GB 2>&1 | tee $RDIR/uring_3disk_perf_stat.txt
echo 950715 | sudo -S ./tiered_setup --destroy --name tv_test_3d 2>&1 || true
sleep 5

echo ""
echo "============================================="
echo "  ALL BENCHMARKS COMPLETE"
echo "============================================="
echo "Run timestamp: ${RUN_TS}"
echo "Raw output in: $RDIR"
ls -la $RDIR/*.txt
