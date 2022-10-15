require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/bay_message'

module Baykit
  module BayServer
    module Bcf

      class BcfParser

        attr :file_name
        attr :line_no
        attr :input
        attr :prev_line_info
        attr :indent_map

        class LineInfo
          attr :line_obj
          attr :indent

          def initialize(line_obj, indent)
            if indent == nil
              raise RuntimeError.new("indent is nil")
            end
            @line_obj = line_obj
            @indent = indent
          end
        end

        def initialize
          @indent_map = []
        end

        def parse(file)
          doc = BcfDocument.new

          @file_name = file
          @line_no = 0
          @input = File.open(file)
          parse_same_level(doc.content_list, 0)
          @input.close
          return doc
        end

        protected

        def push_indent(sp_count)
          @indent_map << sp_count
        end

        def pop_indent
          @indent_map.delete_at(@indent_map.length - 1)
        end

        def get_indent(sp_count)
          if @indent_map.empty?
            push_indent sp_count
          elsif sp_count > @indent_map[indent_map.length - 1]
            push_indent sp_count
          end

          indent = @indent_map.index(sp_count)

          if indent == nil
            raise ParseException.new(@file_name, @line_no, BayMessage.get(:PAS_INVALID_INDENT))
          end

          return indent
        end


        def parse_same_level(cur_list, indent)
          object_exists_in_same_level = false
          while true
            if @prev_line_info != nil
              line_info = @prev_line_info
              @prev_line_info = nil
            else
              line = @input.gets
              @line_no += 1

              if line == nil
                break
              end

              if line.strip.start_with?("#") || line.strip == ""
                next
              end

              line_info = parse_line(@line_no, line)
            end

            if line_info == nil
              # Comment or empty
              next

            elsif line_info.indent > indent
              # lower level
              raise ParseException.new(@file_name, @line_no, BayMessage.get(:PAS_INVALID_INDENT))

            elsif line_info.indent < indent
              # upper level
              @prev_line_info = line_info
              if object_exists_in_same_level
                pop_indent
              end
              return line_info

            else
              object_exists_in_same_level = true

              # samel level
              if line_info.line_obj.instance_of? BcfElement
                # BcfElement
                cur_list << line_info.line_obj

                last_line_info = parse_same_level(line_info.line_obj.content_list, line_info.indent + 1)
                if last_line_info == nil
                  # EOF
                  pop_indent
                  return nil
                else
                  # Same level
                  next
                end
              else
                # IniKeyVal
                cur_list << line_info.line_obj
              end
            end
          end
          pop_indent
          return nil
        end

        def parse_line (line_no, line)

          sp_count = 0
          for sp_count in line.length.times
            c = line[sp_count]
            if c.strip != ''
              # c is not awhitespace
              break
            end

            if c != ' '
              raise ParseException.new(@file_name, @line_no, BayMessage.get(:PAS_INVALID_WHITESPACE))
            end
          end

          indent = get_indent(sp_count)
          line = line.slice(sp_count .. -1)
          line.strip!

          if line.start_with?("[")
            close_pos = line.index("]");
            if close_pos == -1
              raise ParseException.new(@file_name, @line_no, :PAS_BRACE_NOT_CLOSED)
            end

            if !line.end_with?("]")
              raise ParseException.new(@file_name, @line_no, :PAS_INVALID_LINE)
            end

            key_val = parse_key_val(line.slice(1, close_pos - 1), line_no);
            return LineInfo.new(BcfElement.new(key_val.key, key_val.value, @file_name, line_no), indent)
          else
            return LineInfo.new(parse_key_val(line, line_no), indent)
          end
        end

        def parse_key_val(line, line_no)
          sp_pos = line.index(' ')
          key = sp_pos == nil ? line : line[0, sp_pos]
          val = sp_pos == nil ? "" : line[sp_pos .. -1].strip
          return BcfKeyVal.new(key, val, @file_name, line_no);
        end
      end
    end
  end
end