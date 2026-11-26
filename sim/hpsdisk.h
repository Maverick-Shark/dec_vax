// hpsdisk.h - the HPS's side of hps_io's block device interface, for the
// Verilator benches (tb.cpp, cpu_tb/tb_cpu.cpp): the RP07 units' disk
// images, served one 512-byte block at a time the way MiSTer's Main does.
//
// Images (environment DISK0, DISK1):
//
//   file.img[:ro]           an image file, written back on writes (unless
//                           :ro, which also tells the core it is read only)
//   pattern[:sectors][:ro]  a generated disk (default: a full RP07): byte
//                           2k of the sector at LBA L is k, byte 2k+1 is
//                           L ^ L>>8 ^ L>>16 (low bytes); writes are kept in
//                           memory
//
// SDLAT (clocks, default 2000) is the HPS's latency before it answers a
// request; SDTRACE=1 prints every block request.

#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

struct HpsPorts {
	uint32_t *lba[2];
	uint8_t  *rd, *wr, *ack;
	uint16_t *buff_addr;
	uint8_t  *buff_dout, *buff_wr, *din[2];
	uint8_t  *mounted, *readonly;
	uint64_t *size;
};

class HpsDisk {
public:
	struct Disk {
		bool mounted = false, ro = false, pattern = false;
		uint64_t size = 0;
		FILE *f = nullptr;
		std::map<uint32_t, std::vector<uint8_t>> written;
	};
	Disk disk[2];

	void init(const HpsPorts &p) {
		P = p;
		if (getenv("SDLAT")) lat = strtoull(getenv("SDLAT"), 0, 0);
		trace = getenv("SDTRACE") != 0;
		*P.ack = 0; *P.buff_wr = 0; *P.mounted = 0;
		for (int u = 0; u < 2; u++)
			if (const char *spec = getenv(u ? "DISK1" : "DISK0"))
				open(u, spec);
	}

	bool any() const { return disk[0].mounted || disk[1].mounted; }

	// no block request in flight (for a checkpoint)
	bool quiet() const { return st == 0 && !((*P.rd | *P.wr) & 3) && !*P.ack; }

	// the img_mounted pulse for unit u: call with step = 0, 1, 2 on
	// three consecutive clocks
	void mount_step(int u, int step) {
		if (!disk[u].mounted) return;
		if (step == 0) {
			*P.size = disk[u].size;
			*P.readonly = disk[u].ro;
			*P.mounted = 1 << u;
		} else
			*P.mounted = 0;
	}

	static uint8_t pat_byte(uint32_t lba, int i) {
		return (i & 1) ? (uint8_t)(lba ^ (lba >> 8) ^ (lba >> 16)) : (uint8_t)(i >> 1);
	}

	// before every clock edge
	void step(uint64_t cycles) {
		switch (st) {
		case 0:                                 // idle: a request?
			for (int u = 0; u < 2; u++)
				if ((*P.rd | *P.wr) & (1 << u)) {
					unit = u;
					blk = *P.lba[u];
					st = (*P.rd & (1 << u)) ? 1 : 3;
					t = cycles + lat;
					if (trace)
						printf("SD %llu unit %d %s %u\n", (unsigned long long)cycles,
						       u, st == 1 ? "read" : "write", blk);
					break;
				}
			break;
		case 1:                                 // read: after the latency
			if (cycles >= t) {
				rdblk(unit, blk, buf);
				*P.ack = 1 << unit;
				i = 0;
				st = 2;
			}
			break;
		case 2:                                 // a byte every 2 clocks
			if (*P.buff_wr) {
				*P.buff_wr = 0;
				if (++i == 512) { *P.ack = 0; st = 0; }
			} else {
				*P.buff_addr = i;
				*P.buff_dout = buf[i];
				*P.buff_wr = 1;
			}
			break;
		case 3:                                 // write: after the latency
			if (cycles >= t) {
				*P.ack = 1 << unit;
				i = 0;
				*P.buff_addr = 0;
				t = cycles + 2;
				st = 4;
			}
			break;
		case 4:                                 // read the core's buffer
			if (cycles >= t) {
				buf[i] = *P.din[unit];
				if (++i == 512) {
					*P.ack = 0;
					wrblk(unit, blk, buf);
					st = 0;
				} else {
					*P.buff_addr = i;
					t = cycles + 2;
				}
			}
			break;
		}
	}

private:
	HpsPorts P;
	int st = 0, unit = 0, i = 0;
	uint64_t t = 0, lat = 2000;
	uint32_t blk = 0;
	uint8_t buf[512];
	bool trace = false;

	void open(int u, const char *spec) {
		Disk &d = disk[u];
		std::string s(spec);
		if (s.size() > 3 && s.compare(s.size() - 3, 3, ":ro") == 0) {
			d.ro = true;
			s.resize(s.size() - 3);
		}
		if (s.compare(0, 7, "pattern") == 0) {
			d.pattern = true;
			d.size = 1008000ULL * 512;
			if (s.size() > 8 && s[7] == ':')
				d.size = strtoull(s.c_str() + 8, 0, 0) * 512;
		} else {
			d.f = fopen(s.c_str(), d.ro ? "rb" : "r+b");
			if (!d.f) { perror(s.c_str()); exit(1); }
			fseek(d.f, 0, SEEK_END);
			d.size = ftell(d.f);
		}
		d.mounted = true;
	}

	void rdblk(int u, uint32_t lba, uint8_t *b) {
		Disk &d = disk[u];
		if (d.written.count(lba)) { memcpy(b, d.written[lba].data(), 512); return; }
		if (d.pattern) { for (int k = 0; k < 512; k++) b[k] = pat_byte(lba, k); return; }
		memset(b, 0, 512);
		if (d.f && (uint64_t)lba * 512 < d.size) {
			fseek(d.f, (long)lba * 512, SEEK_SET);
			if (fread(b, 1, 512, d.f) != 512) {}
		}
	}

	void wrblk(int u, uint32_t lba, const uint8_t *b) {
		Disk &d = disk[u];
		if (d.pattern || !d.f || d.ro) {
			d.written[lba] = std::vector<uint8_t>(b, b + 512);
			return;
		}
		fseek(d.f, (long)lba * 512, SEEK_SET);
		fwrite(b, 1, 512, d.f);
		fflush(d.f);
	}
};
