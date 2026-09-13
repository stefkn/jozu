module Learning
  def self.config
    @config ||= Config.new
  end

  def self.config=(config)
    @config = config
  end

  def self.reset_config!
    @config = Config.new
  end
end
