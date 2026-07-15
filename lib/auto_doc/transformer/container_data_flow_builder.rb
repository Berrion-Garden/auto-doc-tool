# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Builds data flow records between module roots for the C4 container diagram.
    # Derives flows from cross-module import/require dependencies.
    class ContainerDataFlowBuilder
      # @param analyses [Hash<String, Hash>] Full analysis data
      # @param module_roots [Array<String>] Module root directory paths
      # @return [Array<Hash>] Data flow records with :from, :to, :label
      def self.build(analyses, module_roots)
        flows = []
        return flows if module_roots.size < 2

        # Map files to their module root
        file_to_module = {}
        analyses.each_key do |file_path|
          mod = module_roots.find { |root| file_path.start_with?("#{root}/") }
          file_to_module[file_path] = File.basename(mod) if mod
        end

        # Find cross-module imports
        analyses.each do |file_path, analysis|
          from_mod = file_to_module[file_path]
          next unless from_mod

          imports = analysis[:imports] || []
          imports.each do |imp|
            target_mod = module_roots.find { |root| imp[:path].to_s.include?(File.basename(root)) }
            next unless target_mod

            to_mod = File.basename(target_mod)
            next if from_mod == to_mod

            flow_key = [from_mod, to_mod].sort.join("->")
            next if flows.any? { |f| [f[:from], f[:to]].sort.join("->") == flow_key }

            flows << { from: from_mod, to: to_mod, label: "imports" }
          end
        end

        flows
      end
    end
  end
end
