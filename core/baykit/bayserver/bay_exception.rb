class BayException < StandardError

  def initialize(fmt = nil, *args)
    super(if fmt == nil
            nil
          elsif args == nil || args.length == 0
            sprintf("%s", fmt)
          else
            sprintf(fmt, *args)
          end)
  end
end
