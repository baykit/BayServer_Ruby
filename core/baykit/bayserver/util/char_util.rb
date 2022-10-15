module Baykit
  module BayServer
    module Util
      class CharUtil

        CR = "\r"
        LF = "\n"
        CRLF = "\r\n"

        CR_BYTE = CR.codepoints[0]
        LF_BYTE = LF.codepoints[0]


        def CharUtil.is_ascii(c)
          cp = c.codepoints[0]
          cp >= 32 && cp <= 126
        end
      end
    end
  end
end

