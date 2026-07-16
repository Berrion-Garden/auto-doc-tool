# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class Pipeline
      include MetricsHelper

      STEPS = [
        AgentsOverviewStep.new,
        AgentsMdStep.new,
        ReadmeStep.new,
        IndexSummaryVectorsStep.new,
        DiagramStep.new,
        ArchitectureStep.new,
        ManifestStep.new
      ].freeze

      def initialize(config)
        @config = config
      end

      def run(analyses, target_dir:, output_dir:, module_roots:, say:)
        context = {
          target_dir:    target_dir,
          output_dir:    output_dir,
          config:        @config,
          module_roots:  module_roots,
          analyses:      analyses,
          say:           say,
          all_classes:   0,
          all_methods:   0,
          coverage_pct:  "0",
          schema_tables: nil,
          models:        nil,
          class_hierarchy: [],
          container_data_flows: []
        }

        STEPS.each { |step| step.run(context) }

        # Compile summary stats
        all_cls     = context[:all_classes]
        all_methods = context[:all_methods]
        if all_cls == 0 && context[:analyses].any?
          all_cls, all_methods = count_classes_and_methods(context[:analyses])
        end
        coverage_pct_num = context[:coverage_pct] == "0" ? 0.0 : context[:coverage_pct].to_f

        say.call("", :green)
        say.call("Documentation generation complete.", :green)
        say.call("  #{context[:analyses].size} Ruby files analyzed", :green)
        say.call("  #{all_cls} classes/modules, #{all_methods} methods", :green)

        # created_files count is tracked by orchestrator's wrapped_say and
        # merged into the return hash after pipeline finishes
        say.call("  Documentation coverage: #{coverage_pct_num.round(1)}%", :green)

        {
          project:       File.basename(context[:target_dir]),
          output_dir:    context[:output_dir],
          module_roots:  context[:module_roots].map { |r| File.basename(r) },
          analyses_count: context[:analyses].size,
          classes_count: all_cls,
          methods_count: all_methods,
          coverage_pct:  coverage_pct_num.round(1),
          generated_at:  Time.now.iso8601,
          schema_tables: context[:schema_tables],
          models:        context[:models]
        }
      end

    end
  end
end
