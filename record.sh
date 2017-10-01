#!/bin/bash

mkdir -p /tmp/container_root
sudo debootstrap --arch=amd64 --variant=minbase xenial /tmp/container_root http://archive.ubuntu.com/ubuntu/

# sudo mount --bind /tmp/container_root/ /tmp/container_root/
# sudo mount --make-private /tmp/container_root/
mkdir -p /tmp/container1/upper
mkdir -p /tmp/container1/work
mkdir -p /tmp/container1/merged

sudo mount -t overlay overlay -olowerdir=/tmp/container_root,upperdir=/tmp/container1/upper,workdir=/tmp/container1/work /tmp/container1/merged
sudo mount --make-private /tmp/container1/merged

sudo unshare -fpmnui /bin/bash

pivot_root /tmp/container1/merged/ /tmp/container1/merged/mnt/
mount -t proc proc /proc

capsh --drop=cap_syslog,cap_sys_admin --

ps -f -C unshare

unshare_pid=$(ps -o pid -C unshare --no-headers)

pstree -a -p $unshare_pid

bash_pid=`pstree -a -p $unshare_pid | tail -n 1 | cut -d ',' -f 2`

sudo nsenter -p -m -n -u -i -t $bash_pid

sudo ip link add veth0 type veth peer name veth1
sudo ip link add br0 type bridge
sudo ip link set dev veth1 master br0
sudo ip address add 10.0.0.1/24 dev br0

sudo mkdir -p /var/run/netns
sudo touch /var/run/netns/test
sudo mount --bind /proc/$bash_pid/ns/net /var/run/netns/test

sudo ip link set dev veth0 netns test
sudo ip link set dev veth1 up
sudo ip link set dev br0 up
sudo ip netns exec test ip address add 10.0.0.10/24 dev veth0
sudo ip netns exec test ip link set veth0 up

sudo sysctl -w net.ipv4.ip_forward=1
# sudo iptables -A FORWARD -i br0 -o eth0 -j ACCEPT
# sudo iptables -A FORWARD -i eth0 -o br0 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -s 10.0.0.10/24 -j MASQUERADE
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 6000 -j DNAT --to 10.0.0.10:5000

sudo ip netns exec test ip route add table main default via 10.0.0.1

apt update
apt install -y iproute2

cd /sys/fs/cgroup/cpuset
sudo mkdir test
cd test
sudo bash -c "/bin/echo 0 > cpuset.cpus"
sudo bash -c "/bin/echo 0 > cpuset.mems"
sudo bash -c "/bin/echo $bash_pid > tasks"


for i in $(seq 2); do dd if=/dev/zero of=/dev/null & done


cd /sys/fs/cgroup/cpu
sudo mkdir test
cd test
sudo bash -c "/bin/echo $(($(cat cpu.cfs_period_us)/2)) > cpu.cfs_quota_us"

sudo apt install -y sysstat

cd /sys/fs/cgroup/blkio
sudo mkdir test
devno=`ls -l /dev/xvda | cut -d ' ' -f 5-6 | sed 's/, /:/'`
sudo bash -c "/bin/echo $bash_pid > tasks"
sudo bash -c "/bin/echo \"$devno 100\" > blkio.throttle.write_iops_device"
sudo bash -c "/bin/echo \"$devno 150\" > blkio.throttle.read_iops_device"

while true; do dd if=/dev/zero of=1.img bs=1M count=1024 oflag=direct; done
while true; do dd if=1.img of=/dev/null bs=1M count=1024 iflag=direct; done

apt install -y netcat

sudo tc qdisc add dev veth1 root tbf rate 8000kbit latency 50ms burst 2000
sudo tc qdisc add dev veth1 ingress
sudo tc filter add dev veth1 parent ffff: protocol all u32 match u32 0 0 police rate 16000kbit burst 1m mtu 80kb
