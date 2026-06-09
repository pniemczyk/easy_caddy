# frozen_string_literal: true

require_relative '../registry'
require_relative '../conflicts'

module EasyCaddy
  module Commands
    class Doctor
      def call
        registry = Registry.load
        findings = Conflicts.doctor(registry: registry)

        if findings.empty?
          puts '  All clear — no conflicts or dead upstreams detected.'
          return
        end

        has_block = false
        findings.each do |f|
          label = case f.severity
                  when 'BLOCK' then "\e[31mBLOCK\e[0m"
                  when 'WARN'  then "\e[33mWARN \e[0m"
                  else              "\e[34mINFO \e[0m"
                  end
          puts "  #{label}  #{f.message}"
          puts "         → #{f.hint}"
          has_block = true if f.severity == 'BLOCK'
        end

        exit 1 if has_block
      end
    end
  end
end
