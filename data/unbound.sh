#!/bin/bash

reserved=12582912
availableMemory=$((1024 * $( (grep MemAvailable /proc/meminfo || grep MemTotal /proc/meminfo) | sed 's/[^0-9]//g' ) ))
memoryLimit=$availableMemory
[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ] && memoryLimit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes | sed 's/[^0-9]//g')
[[ ! -z $memoryLimit && $memoryLimit -gt 0 && $memoryLimit -lt $availableMemory ]] && availableMemory=$memoryLimit
if [ $availableMemory -le $(($reserved * 2)) ]; then
    echo "Not enough memory" >&2
    exit 1
fi
availableMemory=$(($availableMemory - $reserved))
rr_cache_size=$(($availableMemory / 3))
msg_cache_size=$(($rr_cache_size / 2))
nproc=$(nproc)
export nproc
if [ "$nproc" -gt 1 ]; then
    threads=$((nproc - 1))
    nproc_log=$(perl -e 'printf "%5.5f\n", log($ENV{nproc})/log(2);')
    rounded_nproc_log="$(printf '%.*f\n' 0 "$nproc_log")"
    slabs=$(( 2 ** rounded_nproc_log ))
else
    threads=1
    slabs=4
fi
if [ ! -f /opt/unbound/etc/unbound/unbound.conf ]; then
    sed \
        -e "s/@MSG_CACHE_SIZE@/${msg_cache_size}/" \
        -e "s/@RR_CACHE_SIZE@/${rr_cache_size}/" \
        -e "s/@THREADS@/${threads}/" \
        -e "s/@SLABS@/${slabs}/" \
        > /opt/unbound/etc/unbound/unbound.conf << EOT
server:
    access-control: 10.0.0.0/8 allow
    access-control: 127.0.0.1/32 allow
    access-control: 172.16.0.0/12 allow
    access-control: 192.168.0.0/16 allow
    aggressive-nsec: yes
    auto-trust-anchor-file: 'var/root.key'
    cache-max-ttl: 86400
    cache-min-ttl: 300
    chroot: '/opt/unbound/etc/unbound'
    delay-close: 10000
    deny-any: yes
    directory: '/opt/unbound/etc/unbound'
    do-daemonize: no
    do-not-query-localhost: no
    ede-serve-expired: yes
    ede: yes
    edns-buffer-size: 1232
    harden-algo-downgrade: yes
    harden-below-nxdomain: yes
    harden-dnssec-stripped: yes
    harden-glue: yes
    harden-large-queries: yes
    harden-referral-path: no
    harden-short-bufsize: yes
    harden-unknown-additional: yes
    hide-http-user-agent: no
    hide-identity: yes
    hide-version: yes
    http-user-agent: 'DNS'
    identity: 'DNS'
    incoming-num-tcp: 10
    infra-cache-slabs: @SLABS@
    interface: 172.18.0.8@5053
    key-cache-slabs: @SLABS@
    log-local-actions: no
    log-queries: no
    log-replies: no
    log-servfail: yes
    logfile: 'unbound.log'
    minimal-responses: yes 
    msg-cache-size: @MSG_CACHE_SIZE@
    msg-cache-slabs: @SLABS@
    neg-cache-size: 4M
    num-queries-per-thread: 4096
    num-threads: @THREADS@
    outgoing-range: 8192
    prefetch-key: yes
    prefetch: no
    private-address: 10.0.0.0/8
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    qname-minimisation: yes
    ratelimit: 1000
    rrset-cache-size: @RR_CACHE_SIZE@
    rrset-cache-slabs: @SLABS@
    rrset-roundrobin: yes
    serve-expired: no
    sock-queue-timeout: 3
    unwanted-reply-threshold: 10000
    use-caps-for-id: yes
    username: '_unbound'
    val-clean-additional: yes
    verbosity: 1
remote-control:
    control-enable: no
EOT
fi 
mkdir -p /opt/unbound/etc/unbound/dev && \
cp -a /dev/random /dev/urandom /dev/null /opt/unbound/etc/unbound/dev/ 
touch /opt/unbound/etc/unbound/unbound.log && \
chown _unbound:_unbound /opt/unbound/etc/unbound/unbound.log && \
chmod 700 /opt/unbound/etc/unbound/unbound.log
mkdir -p -m 700 /opt/unbound/etc/unbound/var && \
chown _unbound:_unbound /opt/unbound/etc/unbound/var && \
/opt/unbound/sbin/unbound-anchor -a /opt/unbound/etc/unbound/var/root.key
exec /opt/unbound/sbin/unbound -d -c /opt/unbound/etc/unbound/unbound.conf