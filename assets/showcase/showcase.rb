# frozen_string_literal: true

require "json"
require "time"

# Photographs every Omarchy theme the same way, so they can be compared.
module ThemePhotograph
  VERSION = "0.1.0"
  SCENES = %i[desktop hero terminal editor btop menu apps lock].freeze

  class Shot
    attr_reader :theme, :scene, :taken_at

    def initialize(theme, scene, width: 1920, height: 1080)
      raise ArgumentError, "unknown scene #{scene}" unless SCENES.include?(scene)

      @theme = theme
      @scene = scene
      @size = [width, height]
      @taken_at = Time.now.utc
    end

    def filename
      "#{theme}/#{scene}.webp"
    end

    def to_h
      { theme:, scene:, size: @size, taken_at: taken_at.iso8601 }
    end
  end

  class Album
    include Enumerable

    def initialize = @shots = []
    def <<(shot) = @shots << shot
    def each(&) = @shots.each(&)

    def by_theme
      group_by(&:theme).transform_values { |shots| shots.map(&:scene) }
    end

    def to_json(*args)
      { version: VERSION, count: count, shots: map(&:to_h) }.to_json(*args)
    end
  end
end

album = ThemePhotograph::Album.new
%w[tokyo-night catppuccin gruvbox].each do |theme|
  ThemePhotograph::SCENES.first(3).each { |scene| album << ThemePhotograph::Shot.new(theme, scene) }
end

puts album.by_theme.inspect
puts album.to_json if ENV.fetch("VERBOSE", "0") =~ /\A(1|true)\z/i
