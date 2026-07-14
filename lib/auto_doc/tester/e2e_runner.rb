# frozen_string_literal: true

require "fileutils"
require "json"

module AutoDoc
  module Tester
    # Runs end-to-end validation of the auto-doc pipeline against itself.
    # Verifies generate, audit, and output file completeness.
    class E2ERunner
      PASS  = "PASS"
      FAIL  = "FAIL"
      WARN  = "WARN"

      def self.run(project_dir = ".")
        new(project_dir).run
      end

      def initialize(project_dir)
        @project_dir = File.expand_path(project_dir)
        @gem_dir = File.expand_path(File.join(__dir__, "../../.."))
        @results = []
      end

      def run
        puts "=" * 60
        puts "auto-doc E2E Self-Test"
        puts "Project: #{@project_dir}"
        puts "=" * 60
        puts

        # Step 0: Clean up any existing .autodoc directory
        autodoc_dir = File.join(@project_dir, ".autodoc")
        step("Clean up existing .autodoc") do
          if File.directory?(autodoc_dir)
            FileUtils.rm_rf(autodoc_dir)
            [true, "Removed #{autodoc_dir}"]
          else
            [true, "Nothing to clean"]
          end
        end

        # Step 1: Generate
        step("Generate docs") do
          output = `ruby -I#{@gem_dir}/lib #{@gem_dir}/exe/auto-doc generate #{@project_dir} 2>&1`
          [$?.success?, output]
        end

        # Step 2: Check output files exist
        step("Check .autodoc/ directory exists") { [File.directory?(autodoc_dir), ""] }

        required_files = [
          "README.md",
          "diagrams/deps.mmd"
        ]
        required_files.each do |file|
          full_path = File.join(autodoc_dir, file)
          step("Check #{file} exists") { [File.exist?(full_path), "Path: #{full_path}"] }
        end

        # Step 3: Check AGENTS.md for each module root
        module_dirs = Dir.glob(File.join(autodoc_dir, "*")).select { |d| File.directory?(d) && File.basename(d) != "diagrams" }
        module_dirs.each do |mod_dir|
          mod_name = File.basename(mod_dir)
          agents_path = File.join(mod_dir, "AGENTS.md")
          step("Check #{mod_name}/AGENTS.md exists") { [File.exist?(agents_path), "Path: #{agents_path}"] }
          if File.exist?(agents_path)
            content = File.read(agents_path)
            step("#{mod_name}/AGENTS.md has content") { [content.length > 50, "#{content.length} bytes"] }
          end
        end

        # Step 4: Run audit (threshold 0 so the command completes even with low coverage)
        step("Run audit") do
          output = `ruby -I#{@gem_dir}/lib #{@gem_dir}/exe/auto-doc audit --threshold 0 #{@project_dir} 2>&1`
          status = $?.success?
          [status, output.lines.first(5).join("  ")]
        end

        # Step 5: Check report.json
        report_path = File.join(autodoc_dir, "report.json")
        step("Check report.json exists") { [File.exist?(report_path), "Path: #{report_path}"] }

        if File.exist?(report_path)
          report = JSON.parse(File.read(report_path))
          step("report.json contains coverage data") { [report.key?("overall_coverage"), "Keys: #{report.keys.join(", ")}"] }
        end

        # Summary
        puts
        puts "=" * 60
        passed = @results.count { |r| r[:status] == PASS }
        failed = @results.count { |r| r[:status] == FAIL }
        puts "Results: #{passed} passed, #{failed} failed, #{@results.size} total"
        puts "=" * 60

        failed == 0
      end

      private

      def step(name)
        print "  #{name}... "
        result, detail = yield
        if result
          @results << { name: name, status: PASS }
          puts "#{PASS}"
        else
          @results << { name: name, status: FAIL, detail: detail }
          puts "#{FAIL}"
          puts "    #{detail}" unless detail.empty?
        end
      end
    end
  end
end
