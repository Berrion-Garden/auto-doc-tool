# frozen_string_literal: true

require "ripper"

module AutoDoc
  module Analyzer
    # Parses Ruby source files using Ripper.sexp to extract classes, modules, and methods.
    # Returns structured analysis data without requiring external dependencies.
    class SourceParser
      # @!attribute [r] name
      #   Name of the definition (class, module, or method)
      # @!attribute [r] type
      #   :class, :module, or :method
      # @!attribute [r] line
      #   Line number where the definition starts
      # @!attribute [r] parent_modules
      #   Array of ancestor module names
      # @!attribute [r] methods
      #   Array of method hashes defined inside this class/module
      Definition = Struct.new(:name, :type, :line, :parent_modules, :methods) do # rubocop:disable Lint/StructNewOverride
        def to_h
          {
            name:           name,
            type:           type,
            line:           line,
            parent_modules: parent_modules.dup,
            methods:        methods.map(&:to_h)
          }
        end
      end

      # Parses a Ruby source file and returns an array of Definition hashes.
      # @param path [String] Path to the Ruby file
      # @return [Array<Hash>] Array of parsed definitions
      def self.parse_file(path)
        return [] unless File.exist?(path)
        new(path).parse
      end

      def initialize(file_path)
        @file_path = file_path
        @code      = File.read(file_path, encoding: "UTF-8")
        @sexp      = Ripper.sexp(@code)
        @definitions = []
        @modules     = []
      end

      # @return [Array<Hash>] Parsed definitions as hashes
      def parse
        return [] if @sexp.nil? || !@sexp.is_a?(Array)

        walk_sexp(@sexp, Definition.new(nil, :top_level, 0, [], []))
        @definitions.map(&:to_h)
      end

      private

      # Recursively walks the S-expression tree from Ripper.sexp()
      def walk_sexp(sexp, current_scope)
        return unless sexp.is_a?(Array) && sexp.length >= 2

        node_type = sexp[0]

        case node_type
        when :program
          # Top-level program node; walk children
          scope = Definition.new(nil, :top_level, 0, [], [])
          Array(sexp[1]).each { |child| walk_sexp(child, scope) }
          @definitions.concat(scope.methods || [])
        when :class
          handle_class(sexp, current_scope.parent_modules.dup)
        when :module
          handle_module(sexp, current_scope.parent_modules.dup)
        when :def, :sclass, :defs, :alias, :cdecl, :massign, :vasgn, :const_path_ref
          # These can be top-level or nested; check if we should record them
          handle_top_level_node(sexp, node_type, current_scope)
        else
          # Recurse into any array child (handles nesting of any depth)
          sexp.each do |child|
            walk_sexp(child, current_scope) if child.is_a?(Array) && child.length >= 2
          end
        end
      end

      def handle_class(sexp, ancestor_modules)
        # S-expressions from Ripper.sexp for class look like:
        # [:class, [:@const, "ClassName", [line, col]], parent_ref, body]
        name_node = sexp[1]
        name      = extract_name(name_node)
        return unless name

        line    = extract_line(name_node)

        scope   = Definition.new(nil, :class_body, 0, ancestor_modules.dup, [])
        body    = sexp[3]
        walk_sexp(body, scope) if body
        @definitions << Definition.new(name, :class, line, ancestor_modules.dup, scope.methods || [])
      end

      def handle_module(sexp, ancestor_modules)
        name_node = sexp[1]
        name      = extract_name(name_node)
        return unless name

        line    = extract_line(name_node)
        child_modules = ancestor_modules.dup + [name]

        scope   = Definition.new(nil, :module_body, 0, child_modules.dup, [])
        body    = sexp[3]
        walk_sexp(body, scope) if body
        @definitions << Definition.new(name, :module, line, ancestor_modules.dup, scope.methods || [])

        # Also walk to find nested definitions within this module context
        if body
          inner_scope = Definition.new(nil, :module_body, 0, child_modules.dup, [])
          walk_sexp(body, inner_scope)
        end
      end

      def handle_top_level_node(sexp, node_type, current_scope)
        case node_type
        when :def, :defs
          name = extract_method_name(sexp)
          line = extract_line_from_sexp(sexp)
          return unless name

          # If we're inside a class or module context, add to that scope's methods
          inside_class_or_module = %i[class_body module_body].include?(current_scope.type)
          if current_scope.respond_to?(:methods) && inside_class_or_module
            current_scope.methods << { name: name, type: :method, line: line }
          else
            @definitions << Definition.new(name, :method, line, [], [])
          end
        end
      end

      # Extracts a constant/method name from various node types
      def extract_name(node)
        return nil unless node.is_a?(Array) && node.length >= 2

        case node[0]
        when :@const, :@ident
          node[1]
        when :const_ref
          # :const_ref wraps a :@const node — unwrap and delegate
          extract_name(node[1])
        when :const_path_ref
          # Nested constant like ::Foo::Bar — join with ::
          parts = extract_const_path(node)
          return nil unless parts
          parts.join("::")
        else
          node[1] if node[1].is_a?(String) && !node[1].empty?
        end
      end

      def extract_method_name(sexp)
        name_node = sexp[1]
        return nil unless name_node.is_a?(Array) && name_node.length >= 2

        case name_node[0]
        when :@ident
          name_node[1]
        when :"@"
          name_node[1]
        else
          name_node[1] if name_node[1].is_a?(String)
        end
      end

      # Resolves ::A::B references to ["A", "B"] for nesting context
      def extract_const_path(node)
        return nil unless node.is_a?(Array)

        case node[0]
        when :const_path_ref
          left  = node[1]
          right = node[2]
          parts = extract_name(left) || extract_const_path(left)
          suffix = (right && right.is_a?(Array)) ? right[1] : nil
          return nil unless parts && suffix
          Array(parts) << suffix
        when :const_path_field
          left  = node[1]
          right = node[2]
          parts = extract_name(left) || extract_const_path(left)
          suffix = (right && right.is_a?(Array)) ? right[1] : nil
          return nil unless parts && suffix
          Array(parts) << suffix
        else
          [node[1]] if node.length > 1 && node[1].is_a?(String)
        end
      end

      def extract_line(node)
        return 0 unless node.is_a?(Array) && node.length >= 2

        # :const_ref wraps an inner node like [:@const, "Name", [line, col]]
        # — unwrap and delegate to get the line number.
        if node[0] == :const_ref
          return extract_line(node[1])
        end

        location = node.last
        return 0 unless location.is_a?(Array) && location.length >= 2
        location[0].respond_to?(:to_i) ? location[0].to_i : 0
      end

      def extract_line_from_sexp(sexp)
        # Ripper sexp has [type, ..., [line, column]] at the end
        return 0 unless sexp.is_a?(Array) && sexp.length >= 3
        location = sexp.last
        return 0 unless location.is_a?(Array) && location.length >= 2
        location[0].respond_to?(:to_i) ? location[0].to_i : 0
      end
    end
  end
end
