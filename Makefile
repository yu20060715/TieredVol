CC=gcc
CFLAGS=-Wall -Wextra -Wpedantic -std=gnu11 -O2
PREFIX=/usr/local

SCHED_OBJS=src/tiered_sched.o src/tiered_partition.o src/tiered_mapper.o \
           src/tiered_io_uring.o src/tiered_metadata.o \
           src/tiered_benchmark.o

SETUP_OBJS=src/setup_discover.o src/setup_bench.o
IO_OBJS=src/io_bench.o

all: tiered_setup tiered_io

tiered_setup: src/tiered_setup.c src/tiered_common.h src/tiered_sched.h src/version.h src/setup_discover.h src/setup_bench.h $(SCHED_OBJS) $(SETUP_OBJS)
	$(CC) $(CFLAGS) -o $@ src/tiered_setup.c $(SCHED_OBJS) $(SETUP_OBJS) -lm -luring

tiered_io: src/tiered_io.c src/tiered_sched.h src/io_bench.h $(SCHED_OBJS) $(IO_OBJS)
	$(CC) $(CFLAGS) -o $@ src/tiered_io.c $(SCHED_OBJS) $(IO_OBJS) -luring

src/tiered_sched.o: src/tiered_sched.c src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/tiered_partition.o: src/tiered_partition.c src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/tiered_mapper.o: src/tiered_mapper.c src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/tiered_io_uring.o: src/tiered_io_uring.c src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/tiered_metadata.o: src/tiered_metadata.c src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/tiered_benchmark.o: src/tiered_benchmark.c src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/setup_discover.o: src/setup_discover.c src/setup_discover.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/setup_bench.o: src/setup_bench.c src/setup_bench.h src/setup_discover.h src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/io_bench.o: src/io_bench.c src/io_bench.h src/tiered_sched.h
	$(CC) $(CFLAGS) -c -o $@ $<

test_common: tests/test_common.c src/tiered_common.h
	$(CC) $(CFLAGS) -o $@ $<

test_mapper: tests/test_mapper.c src/tiered_sched.h $(SCHED_OBJS)
	$(CC) $(CFLAGS) -o $@ $< $(SCHED_OBJS) -luring

test_partition: tests/test_partition.c src/tiered_sched.h $(SCHED_OBJS)
	$(CC) $(CFLAGS) -o $@ $< $(SCHED_OBJS) -luring

test_metadata: tests/test_metadata.c src/tiered_sched.h $(SCHED_OBJS)
	$(CC) $(CFLAGS) -o $@ $< $(SCHED_OBJS) -luring

test_sched: tests/test_sched.c src/tiered_sched.h $(SCHED_OBJS)
	$(CC) $(CFLAGS) -o $@ $< $(SCHED_OBJS) -luring

TEST_LOOP_IMG = /tmp/tv_test.img
TEST_LOOP_DEV = /dev/loop0

test_integrity: tests/test_integrity.c src/tiered_sched.h $(SCHED_OBJS)
	$(CC) $(CFLAGS) -o $@ $< $(SCHED_OBJS) -luring

setup-test-device:
	dd if=/dev/zero of=$(TEST_LOOP_IMG) bs=1M count=100 2>/dev/null
	losetup $(TEST_LOOP_DEV) $(TEST_LOOP_IMG) 2>/dev/null; true

teardown-test-device:
	-losetup -d $(TEST_LOOP_DEV) 2>/dev/null
	-rm -f $(TEST_LOOP_IMG)

test: test_common test_mapper test_partition test_metadata test_sched test_integrity
	@echo "=== test_common ===" && ./test_common && \
	echo "=== test_mapper ===" && ./test_mapper && \
	echo "=== test_partition ===" && ./test_partition && \
	echo "=== test_metadata ===" && ./test_metadata && \
	echo "=== test_sched ===" && ./test_sched && \
	echo "=== test_integrity ===" && ./test_integrity $(TEST_LOOP_DEV)

install: all
	install -m 755 tiered_setup $(DESTDIR)$(PREFIX)/bin/tiered_setup
	install -m 755 tiered_io $(DESTDIR)$(PREFIX)/bin/tiered_io
	install -m 755 scripts/tieredvol-restore.sh $(DESTDIR)$(PREFIX)/bin/tieredvol-restore.sh
	mkdir -p $(DESTDIR)/etc/tieredvol
	mkdir -p $(DESTDIR)/etc/systemd/system
	install -m 644 scripts/tieredvol-restore.service $(DESTDIR)/etc/systemd/system/tieredvol-restore.service
	@echo ""
	@echo "Installed:"
	@echo "  $(DESTDIR)$(PREFIX)/bin/tiered_setup"
	@echo "  $(DESTDIR)$(PREFIX)/bin/tiered_io"
	@echo "  $(DESTDIR)$(PREFIX)/bin/tieredvol-restore.sh"
	@echo "  $(DESTDIR)/etc/systemd/system/tieredvol-restore.service"
	@echo ""
	@echo "To enable auto-restore on boot:"
	@echo "  sudo systemctl daemon-reload"
	@echo "  sudo systemctl enable tieredvol-restore"

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/tiered_setup
	rm -f $(DESTDIR)$(PREFIX)/bin/tiered_io
	rm -f $(DESTDIR)$(PREFIX)/bin/tieredvol-restore.sh
	rm -f $(DESTDIR)/etc/systemd/system/tieredvol-restore.service

clean:
	rm -f tiered_setup tiered_io test_common test_mapper test_partition test_metadata test_sched test_integrity
	rm -f src/*.o

.PHONY: all install uninstall clean test
