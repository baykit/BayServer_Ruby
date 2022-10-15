require 'baykit/bayserver/docker/built_in/log_item'

module Baykit
  module BayServer
    module Docker
      module BuiltIn

        module LogItems
          #
          # Return static text
          #
          class TextItem < LogItem
            attr :text

            def initialize(text)
              @text = text
            end

            def get_item(tour)
              return @text
            end
          end

          #
          # Return null result
          #
          class NullItem < LogItem
            def get_item(tur)
              return nil
            end
          end

          #
          # Return remote IP address (%a)
          #
          class RemoteIpItem < LogItem
            def get_item(tur)
              return tur.req.remote_address
            end
          end

          #
          # Return local IP address (%A)
          #
          class ServerIpItem < LogItem
            def get_item(tur)
              return tur.sever_address
            end
          end

          #
          # Return number of bytes that is sent from clients (Except HTTP headers)
          # (%B)
          #
          class RequestBytesItem1 < LogItem
            def get_item(tur)
              bytes = tur.req.headers.content_length
              if bytes < 0
                bytes = 0
              end
              return bytes.to_s
            end
          end

          #
          # Return number of bytes that is sent from clients in CLF format (Except
          # HTTP headers) (%b)
          #
          class RequestBytesItem2 < LogItem
            def get_item(tur)
              bytes = tur.req.headers.content_length
              if bytes <= 0
                return "-"
              else
                return bytes.to_s
              end
            end
          end

          #
          # Return connection status (%c)
          #
          class ConnectionStatusItem < LogItem
            def get_item(tur)
              if tur.aborted?
                return "X"
              else
                return "-"
              end
            end
          end

          #
          # Return file name (%f)
          #
          class FileNameItem < LogItem
            def get_item(tur)
              return tur.req.script_name
            end
          end


          #
          # Return remote host name (%H)
          #
          class RemoteHostItem < LogItem
            def get_item(tur)
              return tur.req.remote_host()
            end
          end

          #
          # Return remote log name (%l)
          #
          class RemoteLogItem < LogItem
            def get_item(tur)
              return nil
            end
          end

          #
          # Return request protocol (%m)
          #
          class ProtocolItem < LogItem
            def get_item(tur)
              return tur.req.protocol
            end
          end

          #
          # Return requested header (%{Foobar}i)
          #
          class RequestHeaderItem < LogItem

            # Header name
            attr :name

            def init(param)
              if param == nil
                param = ""
              end
              @name = param
            end

            def get_item(tur)
              return tur.req.headers.get(@name)
            end
          end

          #
          # Return request method (%m)
          #
          class MethodItem < LogItem
            def get_item(tur)
              return tur.req.method
            end
          end

          #
          # Return responde header (%{Foobar}o)
          #
          class ResponseHeaderItem < LogItem
            # Header name
            attr :name

            def init(param)
              if param == nil
                param = ""
              end
              @name = param
            end

            def get_item(tur)
              return tur.res.headers.get(@name)
            end
          end


          #
          # The server port (%p)
          #
          class PortItem < LogItem
            def get_item(tur)
              return tur.req.server_port
            end
          end


          #
          # Return query string (%q)
          #
          class QueryStringItem < LogItem
            def get_item(tur)
              qStr = tur.query_string
              if qStr != nil
                return '?' + qStr
              else
                return ""
              end
            end
          end

          #
          # The start line (%r)
          #
          class StartLineItem < LogItem
            def get_item(tur)
              return "#{tur.req.method} #{tur.req.uri} #{tur.req.protocol}"
            end
          end

          #
          # Return status (%s)
          #
          class StatusItem < LogItem
            def get_item(tur)
              return tur.res.headers.status
            end
          end

          #
          #  Return current time (%{format}t)
          #
          class TimeItem < LogItem

            # format
            attr :format

            def init(param)
              if param == nil
                @format  = "[%d/%m/%Y %H:%M:%S %Z]"
              else
                @format = param
              end
            end

            def get_item(tur)
              return Time.now.strftime(@format)
            end
          end

          #
          # Return how long request took (%T)
          #
          class IntervalItem < LogItem
            def get_item(tur)
              return (tur.interval / 1000).to_s
            end
          end

          #
          # Return remote user (%u)
          #
          class RemoteUserItem < LogItem
            def get_item(tur)
              return tur.req.remote_user
            end
          end

          #
          # Return requested URL(not content query string) (%U)
          #
          class RequestUrlItem < LogItem
            def get_item(tur)
              url = tur.req.uri== nil ? "" : tur.req.uri
              pos = url.index('?')
              if pos != nil
                url = url[0, pos]
              end
              return url
            end
          end

          #
          # Return the server name (%v)
          #
          class ServerNameItem < LogItem
            def get_item(tur)
              return tur.req.server_name
            end
          end
        end

      end
    end
  end
end