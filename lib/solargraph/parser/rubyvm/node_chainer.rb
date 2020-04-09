# frozen_string_literal: true

module Solargraph
  module Parser
    module Rubyvm
      # A factory for generating chains from nodes.
      #
      class NodeChainer
        include Rubyvm::NodeMethods

        Chain = Source::Chain

        # @param node [Parser::AST::Node]
        # @param filename [String]
        def initialize node, filename = nil, in_block = false
          @node = node
          @filename = filename
          @in_block = in_block
        end

        # @return [Source::Chain]
        def chain
          links = generate_links(@node)
          Chain.new(links, @node)
        end

        class << self
          # @param node [Parser::AST::Node]
          # @param filename [String]
          # @return [Source::Chain]
          def chain node, filename = nil, in_block = false
            NodeChainer.new(node, filename, in_block).chain
          end

          # @param code [String]
          # @return [Source::Chain]
          def load_string(code)
            node = Parser.parse(code.sub(/\.$/, ''))
            chain = NodeChainer.new(node).chain
            chain.links.push(Chain::Link.new) if code.end_with?('.')
            chain
          end
        end

        private

        # @param n [Parser::AST::Node]
        # @return [Array<Chain::Link>]
        def generate_links n
          return [] unless Parser.is_ast_node?(n)
          return generate_links(n.children[2]) if n.type == :SCOPE
          result = []
          if n.type == :ITER
            @in_block = true
            result.concat generate_links(n.children[0])
            @in_block = false
          elsif n.type == :CALL || n.type == :OPCALL
            n.children[0..-3].each do |c|
              result.concat generate_links(c)
            end
            args = []
            if n.children.last && [:ZARRAY, :ARRAY, :LIST].include?(n.children.last.type)
              n.children.last.children[0..-2].each do |c|
                args.push NodeChainer.chain(c)
              end
            elsif n.children.last && n.children.last.type == :BLOCK_PASS
              args.push NodeChainer.chain(n.children.last)
            end
            result.push Chain::Call.new(n.children[-2].to_s, args, @in_block || block_passed?(n))
          elsif n.type == :ATTRASGN
            result.concat generate_links(n.children[0])
            result.push Chain::Call.new(n.children[1].to_s, nodes_to_argchains(n.children[2].children[0..-2]), @in_block || block_passed?(n))
          elsif n.type == :VCALL
            result.push Chain::Call.new(n.children[0].to_s, [], @in_block || block_passed?(n))
          elsif n.type == :FCALL
            if n.children[1]
              if n.children[1].type == :ARRAY
                result.push Chain::Call.new(n.children[0].to_s, nodes_to_argchains(n.children[1].children[0..-2]), @in_block || block_passed?(n))
              else
                # @todo Assuming BLOCK_PASS
                result.push Chain::BlockVariable.new("&#{n.children[1].children[0].to_s}")
              end
            else
              result.push Chain::Call.new(n.children[0].to_s, [], @in_block || block_passed?(n))
            end
          elsif n.type == :SELF
            result.push Chain::Head.new('self')
          elsif [:SUPER, :ZSUPER].include?(n.type)
            result.push Chain::Head.new('super')
          elsif [:COLON2, :COLON3, :CONST].include?(n.type)
            const = unpack_name(n)
            result.push Chain::Constant.new(const)
          elsif [:LVAR, :LASGN, :DVAR].include?(n.type)
            result.push Chain::Call.new(n.children[0].to_s)
          elsif [:IVAR, :IASGN].include?(n.type)
            result.push Chain::InstanceVariable.new(n.children[0].to_s)
          elsif [:CVAR, :CVASGN].include?(n.type)
            result.push Chain::ClassVariable.new(n.children[0].to_s)
          elsif [:GVAR, :GASGN].include?(n.type)
            result.push Chain::GlobalVariable.new(n.children[0].to_s)
          elsif n.type == :OP_ASGN_OR
            result.concat generate_links n.children[2]
          elsif [:class, :module, :def, :defs].include?(n.type)
            # @todo Undefined or what?
            result.push Chain::UNDEFINED_CALL
          elsif n.type == :AND
            result.concat generate_links(n.children.last)
          elsif n.type == :OR
            result.push Chain::Or.new([NodeChainer.chain(n.children[0], @filename), NodeChainer.chain(n.children[1], @filename)])
          elsif n.type == :begin
            result.concat generate_links(n.children[0])
          elsif n.type == :BLOCK_PASS
            result.push Chain::BlockVariable.new("&#{n.children[1].children[0].to_s}")
          else
            lit = infer_literal_node_type(n)
            result.push (lit ? Chain::Literal.new(lit) : Chain::Link.new)
          end
          result
        end

        def block_passed? node
          node.children.last.is_a?(RubyVM::AbstractSyntaxTree::Node) && node.children.last.type == :BLOCK_PASS
        end

        def nodes_to_argchains nodes
          nodes.map { |node| Parser.chain(node) }
        end
      end
    end
  end
end
