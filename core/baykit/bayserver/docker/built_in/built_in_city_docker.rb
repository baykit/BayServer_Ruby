require 'cgi'
require 'baykit/bayserver/config_exception'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/docker/package'
require 'baykit/bayserver/docker/send_file/send_file_docker'
require 'baykit/bayserver/docker/built_in/built_in_town_docker'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/url_decoder'
require 'baykit/bayserver/tours/tour'

module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class BuiltInCityDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::City  # implements

          include Baykit::BayServer::Util
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Docker
          include Baykit::BayServer::Docker::SendFile
          include Baykit::BayServer::Docker::BuiltIn
          include Baykit::BayServer::Agent

          class  ClubMatchInfo
            attr_accessor :club
            attr_accessor :script_name
            attr_accessor :path_info

            def initialize
              @club = nil
              @script_name = nil
              @path_info = nil
            end
          end

          class MatchInfo
            attr_accessor :town
            attr_accessor :club_match
            attr_accessor :query_string
            attr_accessor :redirect_uri
            attr_accessor :rewritten_uri
          end

          attr :towns
          attr :default_town

          attr :clubs
          attr :default_club

          attr :log_list
          attr :permission_list

          attr :trouble
          attr :name

          def initialize()
            @towns = []
            @clubs = []
            @log_list = []
            @permission_list = []
          end

          def to_s
            "City[#{@name}]"
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            @name = elm.arg
            @towns.sort! { |dkr1, dkr2| dkr2.name.length <=> dkr1.name.length }

            @towns.each do |t|
              BayLog.info(BayMessage.get(:MSG_SETTING_UP_TOWN, t.name, t.location))
            end

            @default_town = BuiltInTownDocker.new
            @default_club = SendFileDocker.new
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_docker(dkr)
            if dkr.kind_of?(Baykit::BayServer::Docker::Town)
              @towns << dkr
            elsif dkr.kind_of?(Baykit::BayServer::Docker::Club)
              @clubs << dkr
            elsif dkr.kind_of?(Baykit::BayServer::Docker::Log)
              @log_list << dkr
            elsif dkr.kind_of?(Baykit::BayServer::Docker::Permission)
              @permission_list << dkr
            elsif dkr.kind_of?(Baykit::BayServer::Docker::Trouble)
              @trouble = dkr
            else
              return false
            end
            return true
          end

          def enter(tur)
            BayLog.debug("%s City[%s] Request URI: %s", tur, @name, tur.req.uri)

            tur.city = self
            @permission_list.each do |p|
              p.tour_admitted(tur)
            end

            match_info = get_town_and_club(tur.req.uri)
            if match_info == nil
              raise HttpException.new(HttpStatus::NOT_FOUND, tur.req.uri)
            end

            match_info.town.tour_admitted(tur)

            if match_info.redirect_uri != nil
              raise HttpException.moved_temp(match_info.redirect_uri)
            else
              BayLog.debug("%s Town[%s] Club[%s]", tur, match_info.town.name(), match_info.club_match.club)

              tur.req.query_string = match_info.query_string
              tur.req.script_name = match_info.club_match.script_name

              if StringUtil.set?(match_info.club_match.club.charset)
                tur.req.charset = match_info.club_match.club.charset
                tur.res.charset = match_info.club_match.club.charset
              else
                tur.req.charset = BayServer.harbor.charset
                tur.res.charset = BayServer.harbor.charset
              end

              tur.req.path_info = match_info.club_match.path_info
              if StringUtil.set?(tur.req.path_info) && match_info.club_match.club.decode_path_info
                tur.req.path_info = CGI.unescape(tur.req.path_info, Encoding::ASCII_8BIT)
              end

              if match_info.rewritten_uri
                tur.req.rewritten_uri = match_info.rewritten_uri # URI is rewritten
              end

              clb = match_info.club_match.club
              tur.town = match_info.town
              tur.club = clb
              clb.arrive(tur)
            end
          end

          def log(tur)
            @log_list.each do |dkr|
              begin
                dkr.log(tur)
              rescue => e
                BayLog.error_e(e)
              end
            end
          end

          private
          def club_maches(club_list, rel_uri, town_name)

            cmi = ClubMatchInfo.new()
            any_club = nil

            club_list.each do |clb|
              if clb.file_name == "*" && clb.extension == nil
                # Ignore any match club
                any_club = clb
                break
              end
            end

            # search for club
            rel_script_name = ""
            catch(:loop) do
              rel_uri.split("/").each do |fname|
                if rel_script_name != ""
                  rel_script_name += "/";
                end
                rel_script_name += fname

                club_list.each do |clb|
                  if clb == any_club
                    # Ignore any match club
                    next
                  end

                  if clb.matches(fname)
                    cmi.club = clb;
                    throw :loop
                  end
                end
              end
            end

            if cmi.club == nil && any_club != nil
              cmi.club = any_club
            end

            if cmi.club == nil
              return nil
            end

            if town_name == "/" && rel_script_name == ""
              cmi.script_name = "/"
              cmi.path_info = nil
            else
              cmi.script_name = town_name + rel_script_name
              if rel_script_name.length == rel_uri.length
                cmi.path_info = nil
              else
                cmi.path_info = rel_uri[rel_script_name.length .. -1]
              end
            end

            return cmi
          end

          def get_town_and_club(req_uri)
            if req_uri == nil
              raise RuntimeError.new("Req uri is nil")
            end
            mi = MatchInfo.new()

            uri = req_uri
            pos = uri.index('?')
            if pos != nil
              mi.query_string = uri[pos + 1 .. -1]
              uri = uri[0, pos]
            end

            @towns.each do |t|
              mtype = t.matches(uri)
              if mtype == Baykit::BayServer::Docker::Town::MATCH_TYPE_NOT_MATCHED
                next
              end

              # town matched
              mi.town = t
              if mtype == Baykit::BayServer::Docker::Town::MATCH_TYPE_CLOSE
                mi.redirect_uri = uri + "/"
                if mi.query_string != nil
                  mi.redirect_uri += mi.query_string
                end
                return mi
              end

              org_uri = uri
              uri = t.reroute(uri)
              if uri != org_uri
                mi.rewritten_uri = uri
              end

              rel = uri[t.name.length .. -1]

              mi.club_match = club_maches(t.clubs, rel, t.name)
              if mi.club_match == nil
                mi.club_match = club_maches(@clubs, rel, t.name)
              end

              if mi.club_match == nil
                # check index file
                if uri.end_with?("/") && !StringUtil.empty?(t.welcome)

                  index_uri = uri + t.welcome
                  rel_uri = rel + t.welcome
                  index_location = File.join(t.location, rel_uri)
                  if File.file?(index_location)
                    if mi.query_string != nil
                      index_uri += "?" + mi.query_string
                    end

                    m2 = get_town_and_club(index_uri)
                    if m2 != nil
                      # matched
                      m2.rewritten_uri = index_uri
                      return m2
                    end
                  end
                end

                # default club matches
                mi.club_match = ClubMatchInfo.new()
                mi.club_match.club = @default_club
                mi.club_match.script_name = nil
                mi.club_match.path_info = nil
              end
              return mi
            end

            return nil
          end

        end
      end
    end
  end
end
