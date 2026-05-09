require 'croute'
require 'openssl'

require 'baykit/bayserver/docker/h3/qic_protocol_handler'
require 'baykit/bayserver/docker/h3/qic_inbound_handler'

module Baykit
  module BayServer
    module Docker
      module H3
        # QicTransporter is installed as the single "transporter" for the UDP
        # socket. It demultiplexes incoming QUIC packets by DCID and routes
        # them to per-connection InboundShip/QicProtocolHandler instances.
        class QicTransporter

          CONN_ID_LEN    = 16
          MAX_PKT_BUF    = 1350

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Common
          include Baykit::BayServer::Protocol

          # ship_map: hex(dcid) => { ship: InboundShip, proto: QicProtocolHandler }
          @@ship_map = {}
          @@ship_map_lock = Mutex.new

          attr_reader :rudder, :port_dkr, :agent_id, :multiplexer
          attr_reader :local_addr

          def initialize
            @rudder     = nil
            @port_dkr   = nil
            @agent_id   = nil
            @multiplexer = nil
            @local_addr  = nil
            # HMAC seed for deriving stable conn IDs
            @conn_id_seed = OpenSSL::Random.random_bytes(32)
            # server name bytes for stateless retry token
            @server_name_bytes = BayServer.get_software_name.b
            # scratch for version-negotiation / retry outgoing packets
            @tmp_post_pkt  = nil
            @tmp_post_addr = nil
          end

          def to_s
            "agt##{@agent_id} udp"
          end

          # GrandAgent.on_read accesses transporter.ship and transporter.server_mode
          # when ProtocolException is raised. QicTransporter routes to multiple ships
          # so we return nil/true as safe defaults.
          def ship = nil
          def server_mode = true
          def secure = false

          def init_udp(agent_id, rudder, multiplexer, port_dkr)
            @agent_id   = agent_id
            @rudder     = rudder
            @multiplexer = multiplexer
            @port_dkr   = port_dkr
            @local_addr  = Croute::Quic::Address.new("0.0.0.0", port_dkr.port)
          end

          # Called by the multiplexer when a UDP datagram arrives.
          # `buf` is a binary String, `adr` is the sender Addrinfo (or [family, port, host, ip]).
          def on_read(rd, buf, adr)
            packet_buf = buf.b

            BayLog.trace("%s notifyRead %d bytes", self, packet_buf.bytesize)

            hdr = begin
              Croute::Quic::PacketHeader.parse(packet_buf, packet_buf.bytesize, CONN_ID_LEN)
            rescue Croute::Error => e
              BayLog.error("%s Header parse error: %s(%d)", self, e.message, e.code)
              return NextSocketAction::CONTINUE
            end

            BayLog.debug("%s packet received: type=%d version=%d", self, hdr.type, hdr.version)

            sip = find_ship(hdr.dcid)

            if sip.nil?
              if hdr.type != 1  # PACKET_TYPE_INITIAL = 1
                BayLog.warn("Client not registered (type=%d)", hdr.type)
              else
                sip = create_ship(hdr, adr)
              end
            end

            sip.notify_read(packet_buf) if sip

            post_all_packets
            cleanup_connections

            NextSocketAction::CONTINUE
          end

          def on_connected(rd)
            # UDP sockets are connectionless; nothing to do
            NextSocketAction::CONTINUE
          end

          def on_error(rd, e)
            BayLog.error_e(e)
          end

          def on_closed(rd)
          end

          def req_read(rd)
            @multiplexer.req_read(rd)
          end

          def req_write(rd, buf, ofs, len, adr, tag, flush, &lis)
            @multiplexer.req_write(rd, buf, ofs, len, adr, tag, flush, &lis)
          end

          def req_close(rd)
            @multiplexer.req_close(rd)
          end

          def check_timeout(rd, duration_sec)
            false
          end

          def get_read_buffer_size
            MAX_PKT_BUF
          end

          def reset
          end

          def print_usage(indent)
          end

          ##############################################################
          # Private
          ##############################################################

          private

          def create_ship(hdr, adr)
            unless Croute::Quic::Quiche.version_is_supported(hdr.version)
              negotiate_version(hdr, adr)
              return nil
            end

            if hdr.token.empty?
              retry_connection(hdr, adr)
              return nil
            end

            peer_ip   = extract_ip(adr)
            odcid = validate_token(hdr.token, peer_ip)
            if odcid.nil?
              BayLog.error("%s Invalid address validation token", self)
              return nil
            end

            scid = hdr.dcid  # reuse the DCID from our Retry response

            peer_addr  = make_address(adr)
            con = Croute::Quic::Connection.accept(
              scid:       scid,
              odcid:      odcid,
              local_addr: @local_addr,
              peer_addr:  peer_addr,
              config:     @port_dkr.quic_config
            )

            BayLog.info("%s New connection scid=%s", self, as_hex(scid))

            agt  = GrandAgent.get(@agent_id)
            h3_config = @port_dkr.h3_config

            ib_handler = QicInboundHandler.new
            proto_hnd  = QicProtocolHandler.new(
              ib_handler, con, adr, @local_addr, peer_addr, h3_config, @multiplexer)
            ib_handler.init(proto_hnd)

            sip = InboundShip.new
            sip.init_inbound(@rudder, @agent_id, self, @port_dkr, proto_hnd)
            proto_hnd.ship = sip

            add_ship(scid, sip)
            sip
          end

          def find_ship(dcid)
            @@ship_map_lock.synchronize { @@ship_map[as_hex(dcid)] }
          end

          def add_ship(scid, sip)
            @@ship_map_lock.synchronize { @@ship_map[as_hex(scid)] = sip }
          end

          # Stateless retry token: server_name_bytes + peer_ip_bytes + dcid
          def mint_token(hdr, peer_ip)
            addr = begin
              IPAddr.new(peer_ip).hton
            rescue => e
              peer_ip.b
            end
            @server_name_bytes + addr + hdr.dcid
          end

          def validate_token(token, peer_ip)
            n = @server_name_bytes.bytesize
            return nil if token.bytesize <= n
            return nil if token.byteslice(0, n) != @server_name_bytes

            addr = begin
              IPAddr.new(peer_ip).hton
            rescue => e
              peer_ip.b
            end
            rest = token.byteslice(n, token.bytesize - n)
            return nil if rest.bytesize < addr.bytesize
            return nil if rest.byteslice(0, addr.bytesize) != addr

            rest.byteslice(addr.bytesize, rest.bytesize - addr.bytesize)
          end

          def negotiate_version(hdr, adr)
            BayLog.info("%s Invalid quic version: %d. Start version negotiation", self, hdr.version)
            out = "\0".b * MAX_PKT_BUF
            n = Croute::Quic::Quiche.negotiate_version(hdr.scid, hdr.dcid, out)
            @tmp_post_pkt  = out.byteslice(0, n)
            @tmp_post_addr = adr
          end

          def retry_connection(hdr, adr)
            new_scid = OpenSSL::Random.random_bytes(CONN_ID_LEN)
            peer_ip  = extract_ip(adr)
            BayLog.info("%s Empty quic token. Retry scid=%s dcid=%s newid=%s",
              self, as_hex(hdr.scid), as_hex(hdr.dcid), as_hex(new_scid))

            token = mint_token(hdr, peer_ip)
            out = "\0".b * MAX_PKT_BUF
            n = Croute::Quic::Quiche.retry(hdr.scid, hdr.dcid, new_scid, token, hdr.version, out)
            @tmp_post_pkt  = out.byteslice(0, n)
            @tmp_post_addr = adr
          end

          # Flush @tmp_post_pkt (version-negotiation / retry) and each
          # connection's queued outgoing packets.
          def post_all_packets
            if @tmp_post_pkt
              pkt = @tmp_post_pkt
              adr = @tmp_post_addr
              @tmp_post_pkt  = nil
              @tmp_post_addr = nil
              @multiplexer.req_write(@rudder, pkt, 0, pkt.bytesize, adr, pkt, true) {}
            end

            @@ship_map_lock.synchronize { @@ship_map.values }.each do |sip|
              proto = sip.protocol_handler
              proto.post_packets if proto.is_a?(QicProtocolHandler)
            end
          end

          def cleanup_connections
            @@ship_map_lock.synchronize do
              @@ship_map.delete_if do |key, sip|
                if sip.protocol_handler.is_a?(QicProtocolHandler) &&
                   sip.protocol_handler.closed?
                  BayLog.debug("%s cleaning up conn=%s", self, key)
                  true
                else
                  false
                end
              end
            end
          end

          def make_address(adr)
            ip, port = extract_ip_port(adr)
            Croute::Quic::Address.new(ip, port)
          end

          def extract_ip(adr)
            extract_ip_port(adr).first
          end

          def extract_ip_port(adr)
            # recvfrom returns [family, port, hostname, ipaddr] in index 1..3
            if adr.is_a?(Array)
              [adr[3], adr[1]]
            elsif adr.respond_to?(:ip_address)
              [adr.ip_address, adr.ip_port]
            else
              [adr.to_s, 0]
            end
          end

          def as_hex(bytes)
            return "null" if bytes.nil?
            bytes.unpack1("H*")
          end
        end
      end
    end
  end
end
