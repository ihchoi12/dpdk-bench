-- RX/TX Rate Measurement Script (based on measure-tx-rate.lua)

-- Since we run from Pktgen-DPDK directory, just add current directory to path
package.path = package.path .. ";./?.lua;?.lua;test/?.lua;app/?.lua;"

require "Pktgen"

local port = 0
local sleeptime = tonumber(os.getenv("PKTGEN_DURATION")) or 10
local packet_size = tonumber(os.getenv("PKTGEN_PACKET_SIZE")) or 64

-- MAC addresses from environment (REQUIRED - set by run script from system.config)
local src_mac = os.getenv("PKTGEN_SRC_MAC")
local dst_mac = os.getenv("PKTGEN_DST_MAC")

-- Validate required environment variables
if not src_mac or src_mac == "" then
    print("ERROR: PKTGEN_SRC_MAC environment variable not set")
    print("       Run 'entry.sh' option 1 to configure system.config")
    os.exit(1)
end
if not dst_mac or dst_mac == "" then
    print("ERROR: PKTGEN_DST_MAC environment variable not set")
    print("       Run 'entry.sh' option 1 to configure system.config")
    os.exit(1)
end

print("Configuration:")
print("  Source MAC (PKTGEN): " .. src_mac)
print("  Dest MAC (L3FWD):    " .. dst_mac)
print("  Packet Size:         " .. packet_size)
print("  Duration:            " .. sleeptime .. "s")

pktgen.stop(port)
pktgen.clear(port)
pktgen.clr()
pktgen.delay(100)

-- Configuration (same as measure-tx-rate.lua)
pktgen.set(port, "size", packet_size)
pktgen.set(port, "rate", 100)  -- 100% rate to utilize multiple cores
pktgen.set(port, "count", 0)   -- Continuous transmission (0 = infinite)

-- Set MAC addresses
pktgen.set_mac(port, "src", src_mac)
pktgen.set_mac(port, "dst", dst_mac)

-- Set IP addresses (dst must match L3FWD's LPM route: 198.18.0.0/24)
pktgen.set_ipaddr(port, "src", "192.168.0.1")
pktgen.set_ipaddr(port, "dst", "198.18.0.1/24")

-- Set up Range configuration for TCP (same as measure-tx-rate.lua)
pktgen.range.ip_proto("all", "tcp")

-- Set MAC addresses in range
pktgen.range.src_mac(port, "start", src_mac)
pktgen.range.dst_mac(port, "start", dst_mac)

-- Set source IP (fixed)
pktgen.range.src_ip(port, "start", "192.168.0.1")
pktgen.range.src_ip(port, "inc", "0.0.0.0")
pktgen.range.src_ip(port, "min", "192.168.0.1")
pktgen.range.src_ip(port, "max", "192.168.0.1")

-- Set destination IP (must match L3FWD's LPM route: 198.18.0.0/24)
pktgen.range.dst_ip(port, "start", "198.18.0.1")
pktgen.range.dst_ip(port, "inc", "0.0.0.0")
pktgen.range.dst_ip(port, "min", "198.18.0.1")
pktgen.range.dst_ip(port, "max", "198.18.0.1")

-- Set source TCP port (20000-20255, increment by 1, same as measure-tx-rate.lua)
pktgen.range.src_port(port, "start", 20000)
pktgen.range.src_port(port, "inc", 1)
pktgen.range.src_port(port, "min", 10000)
pktgen.range.src_port(port, "max", 60000)

-- Set destination TCP port (fixed at 20000, same as measure-tx-rate.lua)
pktgen.range.dst_port(port, "start", 20000)
pktgen.range.dst_port(port, "inc", 0)
pktgen.range.dst_port(port, "min", 20000)
pktgen.range.dst_port(port, "max", 20000)

-- Set TTL (same as measure-tx-rate.lua)
pktgen.range.ttl(port, "start", 64)
pktgen.range.ttl(port, "inc", 0)
pktgen.range.ttl(port, "min", 64)
pktgen.range.ttl(port, "max", 64)

-- Set packet size for range mode
pktgen.range.pkt_size(port, "start", packet_size)
pktgen.range.pkt_size(port, "inc", 0)
pktgen.range.pkt_size(port, "min", packet_size)
pktgen.range.pkt_size(port, "max", packet_size)

-- Enable range mode (same as measure-tx-rate.lua)
pktgen.set_range(port, "on")

pktgen.delay(100)

-- Start transmission
print("Starting packet transmission for " .. sleeptime .. " seconds")
pktgen.start(port)

pktgen.delay(sleeptime * 1000) -- sleep time in milliseconds

-- Stop transmission BEFORE reading statistics
print("Stopping packet transmission...")
pktgen.stop(port)

-- Wait a bit for any remaining packets to be transmitted by hardware
pktgen.delay(100)

-- Print packet statistics summary after stopping
print("\nPrinting packet statistics summary...")
pktgen.print_stats()

os.exit(0)
