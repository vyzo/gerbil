;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; OS socket interface

(import :std/os/_socket
        :std/os/error
        :std/os/fd
        :std/os/fcntl
        :std/net/address
        :std/text/utf8
        :std/sugar
        :std/contract
        (only-in :gerbil/gambit/ports close-port)
        (for-syntax :std/stxutil))

(export socket
        server-socket
        socket?
        socket-bind
        socket-listen
        socket-accept
        socket-connect
        socket-shutdown
        socket-close
        socket-send
        socket-sendto
        socket-sendmsg
        socket-recv
        socket-recvfrom
        socket-recvmsg
        socket-recvmsg*
        socket-getpeername
        socket-getsockname
        socket-getsockopt
        socket-setsockopt
        socket-domain
        socket-address?
        make-socket-address
        make-socket-address-in
        make-socket-address-in6
        make-socket-address-un
        socket-address
        socket-address-in
        socket-address-in6
        socket-address-un
        socket-address->address
        socket-address->string
        socket-address-family

        ;; constants from _socket
        AF_UNSPEC
        AF_INET
        AF_INET6
        AF_UNIX AF_LOCAL
        AF_NETLINK AF_PACKET AF_ALG

        SOCK_STREAM
        SOCK_DGRAM
        SOCK_RAW
        SOCK_SEQPACKET SOCK_RDM

        SHUT_RD
        SHUT_WR
        SHUT_RDWR

        UNIX_MAX_PATH

        ;; sockopt constants
        SOL_SOCKET
        SO_ACCEPTCONN
        SO_BINDTODEVICE
        SO_BROADCAST
        SO_DEBUG
        SO_DOMAIN
        SO_DONTROUTE
        SO_ERROR
        SO_KEEPALIVE
        SO_LINGER
        SO_OOBLINE
        SO_PASSCRED
        SO_PEERCRED
        SO_PEEK_OFF
        SO_PROTOCOL
        SO_RCVBUF
        SO_SNDBUF
        SO_RCVLOWAT
        SO_SNDLOWAT
        SO_RCVTIMEO
        SO_SNDTIMEO
        SO_REUSEADDR
        SO_REUSEPORT
        SO_TYPE
        SO_TIMESTAMP
        SO_USELOOPBACK

        IPPROTO_IPV6
        IPV6_ADDRFORM
        IPV6_ADD_MEMBERSHIP
        IPV6_DROP_MEMBERSHIP
        IPV6_MTU
        IPV6_MTU_DISCOVER
        IPV6_MULTICAST_HOPS
        IPV6_MULTICAST_IF
        IPV6_MULTICAST_LOOP
        IPV6_RECVPKTINFO
        IPV6_RTHDR
        IPV6_AUTHHDR
        IPV6_DSTOPTS
        IPV6_HOPOPTS
        IPV6_FLOWINFO
        IPV6_HOPLIMIT
        IPV6_ROUTER_ALERT
        IPV6_UNICAST_HOPS
        IPV6_V6ONLY

        IPPROTO_TCP
        TCP_CONGESTION
        TCP_CORK
        TCP_DEFER_ACCEPT
        TCP_KEEPCNT
        TCP_KEEPIDLE
        TCP_KEEPINTVL
        TCP_MAXSEG
        TCP_NODELAY
        TCP_SYNCNT

        IP_PMTUDISC_WANT
        IP_PMTUDISC_DONT
        IP_PMTUDISC_DO
        IP_PMTUDISC_PROBE

        IPTOS_LOWDELAY
        IPTOS_THROUGHPUT
        IPTOS_RELIABILITY
        IPTOS_MINCOST

        MSG_CONFIRM
        MSG_CTRUNC
        MSG_DONTROUTE
        MSG_DONTWAIT
        MSG_EOR
        MSG_ERRQUEUE
        MSG_MORE
        MSG_NOSIGNAL
        MSG_OOB
        MSG_PEEK
        MSG_TRUNC
        MSG_WAITALL
        )

(def (open-socket domain type proto dir)
  (let* ((fd (check-os-error (_socket domain type proto)
               (socket domain type proto)))
         (raw (fdopen fd dir 'socket)))
    (fd-set-nonblock/closeonexec raw)
    raw))

(def (socket domain type (proto 0))
  (open-socket domain type proto 'inout))

(def (server-socket domain type (proto 0))
  (open-socket domain type proto 'in))

(def (socket? obj)
  (fd-type? obj 'socket))

(def (socket-bind sock addr)
  (check-os-error (_bind (fd-e sock) (socket-address addr))
    (socket-bind sock addr)))

(def (socket-listen sock (backlog 10))
  (check-os-error (_listen (fd-e sock) backlog)
    (socket-listen sock backlog)))

(def (socket-accept sock (sa #f))
  (cond-expand
    (linux
     (alet (fd (do-retry-nonblock (_accept4 (fd-e sock) sa)
                 (socket-accept sock sa)
                 EAGAIN EWOULDBLOCK))
       (fdopen fd 'inout 'socket)))
    (else
     (alet (fd (do-retry-nonblock (_accept (fd-e sock) sa)
                 (socket-accept sock sa)
                 EAGAIN EWOULDBLOCK))
       (let (raw (fdopen fd 'inout 'socket))
         (fd-set-nonblock raw)
         (fd-set-closeonexec raw)
         raw)))))

(def (socket-connect sock sa)
  (let (sa (socket-address sa))
    (do-retry-nonblock (_connect (fd-e sock) sa)
      (socket-connect sock sa)
      EINPROGRESS)))

(def (socket-shutdown sock how)
  (check-os-error (_shutdown (fd-e sock) how)
    (socket-shutdown sock how))
  (cond
   ((eq? how SHUT_RD)
    (close-input-port sock))
   ((eq? how SHUT_WR)
    (close-output-port sock))
   ((eq? how SHUT_RDWR)
    (close-port sock))))

(def (socket-close sock)
  (close-port sock))

(def (socket-send sock bytes (start 0) (end (u8vector-length bytes)) (flags 0))
  (do-retry-nonblock (_send (fd-e sock) bytes start end flags)
    (socket-send sock bytes start end flags)
    EAGAIN EWOULDBLOCK))

(def (socket-sendto sock bytes sa (start 0) (end (u8vector-length bytes)) (flags 0))
  (let (sa (socket-address sa))
    (do-retry-nonblock (_sendto (fd-e sock) bytes start end flags sa)
      (socket-sendto sock bytes sa start end flags)
      EAGAIN EWOULDBLOCK)))

(def (socket-sendmsg sock name-bytes io-bytes ctl-bytes flags)
  (do-retry-nonblock (_sendmsg (fd-e sock) name-bytes io-bytes ctl-bytes flags)
    (socket-sendmsg sock name-bytes io-bytes ctl-bytes flags)
    EAGAIN EWOULDBLOCK))

(def (socket-recv sock bytes (start 0) (end (u8vector-length bytes)) (flags 0))
  (do-retry-nonblock (_recv (fd-e sock) bytes start end flags)
    (socket-recv sock bytes start end flags)
    EAGAIN EWOULDBLOCK))

(def (socket-recvfrom sock bytes sa (start 0) (end (u8vector-length bytes)) (flags 0))
  (do-retry-nonblock (_recvfrom (fd-e sock) bytes start end flags sa)
    (socket-recvfrom sock bytes sa start end flags)
    EAGAIN EWOULDBLOCK))

(def (socket-recvmsg* sock name-bytes rname io-bytes ctl-bytes rctl flags rflags)
  (do-retry-nonblock (_recvmsg (fd-e sock)
                               name-bytes rname
                               io-bytes
                               ctl-bytes rctl
                               flags
                               rflags)
    (socket-recvmsg sock name-bytes io-bytes ctl-bytes flags)
    EAGAIN EWOULDBLOCK))

(def (socket-recvmsg sock name io ctl flags)
  (let* ((rname (and name (check-ptr (make_int_ptr))))
         (rctl (and ctl (check-ptr (make_int_ptr))))
         (rflags (make_int_ptr))
         (r (socket-recvmsg* sock name rname io ctl rctl flags rflags)))
    (and r (values r
                   (and rname (int_ptr_value rname))
                   (and rctl (int_ptr_value rctl))
                   (int_ptr_value rflags)))))

(def (socket-getpeername sock (sa #f))
  (let (sa (or sa (make-socket-address (socket-domain sock))))
    (check-os-error (_getpeername (fd-e sock) sa)
      (socket-getpeername sock))
    sa))

(def (socket-getsockname sock (sa #f))
  (let (sa (or sa (make-socket-address (socket-domain sock))))
    (check-os-error (_getsockname (fd-e sock) sa)
      (socket-getsockname sock))
    sa))

(def (socket-domain sock)
  (socket-getsockopt sock SOL_SOCKET SO_DOMAIN))

;;; Socket addresses
(def (socket-address? obj)
  (sockaddr? obj))

(def (make-socket-address af)
  (check-ptr (make_sockaddr af)))

(def (make-socket-address-in)
  (make-socket-address AF_INET))

(def (make-socket-address-in6)
  (make-socket-address AF_INET6))

(def (make-socket-address-un)
  (make-socket-address AF_UNIX))

(def (socket-address-in host port)
  (let* ((ip4 (ip4-address host))
         (sa (make-socket-address-in)))
    (sockaddr_in_addr_set sa ip4)
    (sockaddr_in_port_set sa port)
    sa))

(def (socket-address-in6 host port)
  (let* ((ip6 (ip6-address host))
         (sa (make-socket-address-in6)))
    (sockaddr_in6_addr_set sa ip6)
    (sockaddr_in6_port_set sa port)
    sa))

(def (socket-address-un path)
  (let (pathlen (string-utf8-length path))
    (if (##fx< pathlen UNIX_MAX_PATH)
      (let (sa (make-socket-address-un))
        (sockaddr_un_path_set sa path)
        sa)
      (error "Malformed address; path is too long"))))

(def (socket-address-family sa)
  (sockaddr_family sa))

(def (socket-address addr)
  (cond
   ((socket-address? addr) addr)
   ((or (inet-address? addr)
        (inet-address-string? addr))
    (inet-address->socket-address addr))
   (else
    (socket-address-un addr))))

(def (inet-address->socket-address addr)
  (with ([ip . port] (resolve-address addr))
    (cond
     ((ip4-address? ip)
      (socket-address-in ip port))
     ((ip6-address? ip)
      (socket-address-in6 ip port))
     (else
      (error "Bad address; expected ip4 or ip6 inet-address" addr)))))

(def (socket-address->address sa)
  (let (saf (sockaddr_family sa))
    (cond
     ((eq? saf AF_INET)
      (let* ((ip4 (make-u8vector 4))
             (_ (sockaddr_in_addr sa ip4))
             (port (sockaddr_in_port sa)))
        (cons ip4 port)))
     ((eq? saf AF_INET6)
      (let* ((ip6 (make-u8vector 16))
             (_ (sockaddr_in6_addr sa ip6))
             (port (sockaddr_in6_port sa)))
        (cons ip6 port)))
     ((eq? saf AF_UNIX)
      (sockaddr_un_path sa))
     (else
      (error "Unknown address family" sa saf)))))

(def (socket-address->string sa)
  (let (saf (sockaddr_family sa))
    (cond
     ((eq? saf AF_INET)
      (let* ((ip4 (make-u8vector 4))
             (_ (sockaddr_in_addr sa ip4))
             (port (sockaddr_in_port sa)))
        (string-append (ip4-address->string ip4) ":" (number->string port))))
     ((eq? saf AF_INET6)
      (let* ((ip6 (make-u8vector 16))
             (_ (sockaddr_in6_addr sa ip6))
             (port (sockaddr_in6_port sa)))
        (string-append (ip6-address->string ip6) ":" (number->string port))))
     ((eq? saf AF_UNIX)
      (sockaddr_un_path sa))
     (else
      (error "Unknown address family" sa saf)))))

;;; sockopts
(def (socket-getsockopt sock level opt . args)
  (cond
   ((hash-get socket-sockopts level)
    => (lambda (ht)
         (cond
          ((hash-get ht opt)
           => (match <>
                ((values getf setf)
                 (if getf
                   (apply getf sock level opt args)
                   (error "No getsockopt operation defined for option" level opt)))))
          (else
           (error "Unknown socket option" level opt)))))
   (else
    (error "Unknown socket level" level opt))))

(def (socket-setsockopt sock level opt val . args)
  (cond
   ((hash-get socket-sockopts level)
    => (lambda (ht)
         (cond
          ((hash-get ht opt)
           => (match <>
                ((values getf setf)
                 (if setf
                   (apply setf sock level opt val args)
                   (error "No setsockopt operation defined for option" level opt)))))
          (else
           (error "Unknown socket option" level opt)))))
   (else
    (error "Unknown socket level" level opt))))

(def (socket-getsockopt-int sock level opt)
  (check-os-error (_getsockopt_int (fd-e sock) level opt)
    (socket-getsockopt sock level opt)))

(def/c (socket-setsockopt-int sock level opt val)
  (@contract (fixnum? val))
  (check-os-error (_setsockopt_int (fd-e sock) level opt val)
    (socket-setsockopt sock level opt val)))

(def (socket-getsockopt-tv sock level opt)
  (let (tv (check-ptr (make_tv)))
    (check-os-error (_getsockopt_tv (fd-e sock) level opt tv)
      (socket-getsockopt sock level opt))
    (+ (tv_sec tv) (/ (tv_usec tv) 1e6))))

(def/c (socket-setsockopt-tv sock level opt tm)
  (@contract (real? tm))
  (let* ((tm-sec (floor tm))
         (tm-frac (- tm tm-sec))
         (tm-usec (floor (* tm-frac 1e6)))
         (tv (check-ptr (make_tv))))
    (tv_sec_set tv (inexact->exact tm-sec))
    (tv_usec_set tv (inexact->exact tm-usec))
    (check-os-error (_setsockopt_tv (fd-e sock) level opt tv)
      (socket-setsockopt sock level opt tm))))

(def (socket-getsockopt-addr-in sock level opt)
  (let (sa (make-socket-address-in))
    (check-os-error (_getsockopt_sa (fd-e sock) level opt sa)
      (socket-getsockopt sock level opt))
    sa))

(def (socket-getsockopt-addr-in6 sock level opt)
  (let (sa (make-socket-address-in6))
    (check-os-error (_getsockopt_sa (fd-e sock) level opt sa)
      (socket-getsockopt sock level opt))
    sa))

(def (socket-setsockopt-addr sock level opt addr)
  (let (sa (socket-address addr))
    (check-os-error (_setsockopt_sa (fd-e sock) level opt sa)
      (socket-setsockopt sock level opt addr))))

(def/c (socket-getsockopt-bytes sock level opt bytes)
  (@contract (u8vector? bytes))
  (check-os-error (_getsockopt_bytes (fd-e sock) level opt bytes)
    (socket-getsockopt sock level opt bytes)))

(def/c (socket-setsockopt-bytes sock level opt bytes)
  (@contract (u8vector? bytes))
  (check-os-error (_setsockopt_bytes (fd-e sock) level opt bytes)
    (socket-setsockopt sock level opt bytes)))

(def/c (socket-setsockopt-mreq sock level opt ips)
  (@contract (and (pair? ips) (ip4-address? (car ips)) (ip4-address? (cdr ips))))
  (with ([maddr . laddr] ips)
    (let ((maddr (ip4-address maddr))
          (laddr (ip4-address laddr)))
      (check-os-error (_setsockopt_mreq (fd-e sock) level opt maddr laddr)
        (socket-setsockopt sock level opt ips)))))

(def/c (socket-setsockopt-mreq-src sock level opt ips)
  (@contract (and (list? ips) (andmap ip4-address? ips)))
  (with ([maddr iaddr saddr] ips)
    (let ((maddr (ip4-address maddr))
          (iaddr (ip4-address iaddr))
          (saddr (ip4-address saddr)))
      (check-os-error (_setsockopt_mreq_src (fd-e sock) level opt maddr iaddr saddr)
        (socket-setsockopt sock level opt ips)))))

(def/c (socket-setsockopt-mreq6 sock level opt ips)
  (@contract (and (pair? ips) (ip6-address? (car ips))))
  (with ([maddr . ifindex] ips)
    (let (maddr (ip6-address maddr))
      (check-os-error (_setsockopt_mreq6 (fd-e sock) level opt maddr ifindex)
        (socket-setsockopt sock level opt ips)))))

(def (socket-getsockopt-linger sock level opt)
  (let (linger (check-ptr (make_linger)))
    (check-os-error (_getsockopt_linger sock level opt linger)
      (socket-getsockopt sock level opt))
    (if (##fxzero? (linger_onoff linger))
      #f
      (linger_linger linger))))

(def/c (socket-setsockopt-linger sock level opt val)
  (@contract (or (fixnum? val) (not val)))
  (let (linger (check-ptr (make_linger)))
    (cond
     ((fixnum? val)
      (linger_onoff_set linger 1)
      (linger_linger_set linger val))
     (else                              ; (not val)
      (linger_onoff_set linger 0)
      (linger_linger_set linger 0)))
    (check-os-error (_setsockopt_linger sock level opt linger)
      (socket-setsockopt sock level opt val))))

(def socket-sockopts
  (hash-eq (,SOL_SOCKET (make-hash-table-eq))
           (,IPPROTO_IP (make-hash-table-eq))
           (,IPPROTO_IPV6 (make-hash-table-eq))
           (,IPPROTO_TCP (make-hash-table-eq))))

(defrules defsockopt ()
  ((_ level opt getf setf)
   (when opt
     (hash-put! (hash-ref socket-sockopts level)
                opt
                (values (@sockopt-getf getf) (@sockopt-setf setf))))))

(defsyntax (@sockopt-getf stx)
  (syntax-case stx ()
    ((_ id) (identifier? #'id) (format-id #'id "socket-getsockopt-~a" #'id))
    ((_ #f) #f)))

(defsyntax (@sockopt-setf stx)
  (syntax-case stx ()
    ((_ id) (identifier? #'id) (format-id #'id "socket-setsockopt-~a" #'id))
    ((_ #f) #f)))

;; this list is invariably incomplete, new ones get added all the time
;; add to it and _socket.{ssi,scm} if you are missing something!
(defsockopt SOL_SOCKET SO_ACCEPTCONN            int    #f)
(defsockopt SOL_SOCKET SO_BINDTODEVICE          bytes  bytes)
(defsockopt SOL_SOCKET SO_BROADCAST             int    int)
(defsockopt SOL_SOCKET SO_DEBUG                 int    int)
(defsockopt SOL_SOCKET SO_DOMAIN                int    #f)
(defsockopt SOL_SOCKET SO_DONTROUTE             int    int)
(defsockopt SOL_SOCKET SO_ERROR                 int    #f)
(defsockopt SOL_SOCKET SO_KEEPALIVE             int    int)
(defsockopt SOL_SOCKET SO_LINGER                linger linger)
(defsockopt SOL_SOCKET SO_OOBLINE               int    int)
(defsockopt SOL_SOCKET SO_PASSCRED              int    int)
(defsockopt SOL_SOCKET SO_PEERCRED              bytes  bytes)
(defsockopt SOL_SOCKET SO_PEEK_OFF              int    int)
(defsockopt SOL_SOCKET SO_PROTOCOL              int    int)
(defsockopt SOL_SOCKET SO_RCVBUF                int    int)
(defsockopt SOL_SOCKET SO_SNDBUF                int    int)
(defsockopt SOL_SOCKET SO_RCVLOWAT              int    int)
(defsockopt SOL_SOCKET SO_SNDLOWAT              int    int)
(defsockopt SOL_SOCKET SO_RCVTIMEO              tv     tv)
(defsockopt SOL_SOCKET SO_SNDTIMEO              tv     tv)
(defsockopt SOL_SOCKET SO_REUSEADDR             int    int)
(defsockopt SOL_SOCKET SO_REUSEPORT             int    int)
(defsockopt SOL_SOCKET SO_TYPE                  int    int)
(defsockopt SOL_SOCKET SO_TIMESTAMP             int    int)
(defsockopt SOL_SOCKET SO_USELOOPBACK           int    int)

(defsockopt IPPROTO_IP IP_ADD_MEMBERSHIP         #f     mreq)
(defsockopt IPPROTO_IP IP_DROP_MEMBERSHIP        #f     mreq)
(defsockopt IPPROTO_IP IP_ADD_SOURCE_MEMBERSHIP  #f     mreq-src)
(defsockopt IPPROTO_IP IP_DROP_SOURCE_MEMBERSHIP #f     mreq-src)
(defsockopt IPPROTO_IP IP_BLOCK_SOURCE           #f     mreq-src)
(defsockopt IPPROTO_IP IP_UNBLOCK_SOURCE         #f     mreq-src)
(defsockopt IPPROTO_IP IP_FREEBIND               int    int)
(defsockopt IPPROTO_IP IP_HDRINCL                int    int)
(defsockopt IPPROTO_IP IP_MTU                    int    #f)
(defsockopt IPPROTO_IP IP_MTU_DISCOVER           int    int)
(defsockopt IPPROTO_IP IP_MULTICAST_ALL          int    int)
(defsockopt IPPROTO_IP IP_MULTICAST_IF           #f     mreq)
(defsockopt IPPROTO_IP IP_MULTICAST_LOOP         int    int)
(defsockopt IPPROTO_IP IP_MULTICAST_TTL          int    int)
(defsockopt IPPROTO_IP IP_NODEFRAG               int    int)
(defsockopt IPPROTO_IP IP_OPTIONS                bytes  bytes)
(defsockopt IPPROTO_IP IP_PKTINFO                bytes  bytes)
(defsockopt IPPROTO_IP IP_RECVERR                int    int)
(defsockopt IPPROTO_IP IP_RECVORIGDSTADDR        int    int)
(defsockopt IPPROTO_IP IP_RECVOPTS               int    int)
(defsockopt IPPROTO_IP IP_RECVTOS                int    int)
(defsockopt IPPROTO_IP IP_RECVTTL                int    int)
(defsockopt IPPROTO_IP IP_RETOPTS                int    int)
(defsockopt IPPROTO_IP IP_ROUTER_ALERT           int    int)
(defsockopt IPPROTO_IP IP_TOS                    int    int)
(defsockopt IPPROTO_IP IP_TTL                    int    int)

(defsockopt IPPROTO_IPV6 IPV6_ADDRFORM           #f     int)
(defsockopt IPPROTO_IPV6 IPV6_ADD_MEMBERSHIP     #f     mreq6)
(defsockopt IPPROTO_IPV6 IPV6_DROP_MEMBERSHIP    #f     mreq6)
(defsockopt IPPROTO_IPV6 IPV6_MTU                int    int)
(defsockopt IPPROTO_IPV6 IPV6_MTU_DISCOVER       int    int)
(defsockopt IPPROTO_IPV6 IPV6_MULTICAST_HOPS     int    int)
(defsockopt IPPROTO_IPV6 IPV6_MULTICAST_IF       int    int)
(defsockopt IPPROTO_IPV6 IPV6_MULTICAST_LOOP     int    int)
(defsockopt IPPROTO_IPV6 IPV6_RECVPKTINFO        int    int)
(defsockopt IPPROTO_IPV6 IPV6_RTHDR              int    int)
(defsockopt IPPROTO_IPV6 IPV6_AUTHHDR            int    int)
(defsockopt IPPROTO_IPV6 IPV6_DSTOPTS            int    int)
(defsockopt IPPROTO_IPV6 IPV6_HOPOPTS            int    int)
(defsockopt IPPROTO_IPV6 IPV6_FLOWINFO           int    int)
(defsockopt IPPROTO_IPV6 IPV6_HOPLIMIT           int    int)
(defsockopt IPPROTO_IPV6 IPV6_ROUTER_ALERT       int    int)
(defsockopt IPPROTO_IPV6 IPV6_UNICAST_HOPS       int    int)
(defsockopt IPPROTO_IPV6 IPV6_V6ONLY             int    int)

(defsockopt IPPROTO_TCP TCP_CONGESTION           #f     bytes)
(defsockopt IPPROTO_TCP TCP_CORK                 int    int)
(defsockopt IPPROTO_TCP TCP_DEFER_ACCEPT         int    int)
(defsockopt IPPROTO_TCP TCP_KEEPCNT              int    int)
(defsockopt IPPROTO_TCP TCP_KEEPIDLE             int    int)
(defsockopt IPPROTO_TCP TCP_KEEPINTVL            int    int)
(defsockopt IPPROTO_TCP TCP_MAXSEG               int    int)
(defsockopt IPPROTO_TCP TCP_NODELAY              int    int)
(defsockopt IPPROTO_TCP TCP_SYNCNT               int    int)
