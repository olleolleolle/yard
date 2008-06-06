module YARD
  module Handlers
    class UndocumentableError < Exception; end
    
    # = Handlers 
    # 
    # Handlers are pluggable semantic parsers for YARD's code generation 
    # phase. They allow developers to control what information gets 
    # generated by YARD, giving them the ability to, for instance, document
    # any Ruby DSLs that a customized framework may use. A good example
    # of this would be the ability to document and generate meta data for
    # the 'describe' declaration of the RSpec testing framework by simply
    # adding a handler for such a keyword. Similarly, any Ruby API that
    # takes advantage of class level declarations could add these to the
    # documentation in a very explicit format by treating them as first-
    # class objects in any outputted documentation.
    # 
    # == Overview of a Typical Handler Scenario 
    # 
    # Generally, a handler class will declare a set of statements which
    # it will handle using the {handles} class declaration. It will then
    # implement the {#process} method to do the work. The processing would
    # usually involve the manipulation of the {#namespace}, {#owner} 
    # {CodeObjects::Base code objects} or the creation of new ones, in 
    # which case they should be registered by {#register}, a method that 
    # sets some basic attributes for the new objects.
    # 
    # Handlers are usually simple and take up to a page of code to process
    # and register a new object or add new attributes to the current +namespace+.
    # 
    # == Setting up a Handler for Use 
    # 
    # A Handler is automatically registered when it is subclassed from the
    # base class. The only other thing that needs to be done is to specify
    # which statement the handler will process. This is done with the +handles+
    # declaration, taking either a {Parser::RubyToken}, {String} or {Regexp}.
    # Here is a simple example which processes module statements.
    # 
    #   class MyModuleHandler < YARD::Handlers::Base
    #     handles TkMODULE
    # 
    #     def process
    #       # do something
    #     end
    #   end
    # 
    # == Processing Handler Data 
    # 
    # The goal of a specific handler is really up to the developer, and as 
    # such there is no real guideline on how to process the data. However,
    # it is important to know where the data is coming from to be able to use
    # it.
    # 
    # === +statement+ Attribute 
    # 
    # The +statement+ attribute pertains to the {Parser::Statement} object
    # containing a set of tokens parsed in by the parser. This is the main set
    # of data to be analyzed and processed. The comments attached to the statement
    # can be accessed by the {Parser::Statement#comments} method, but generally
    # the data to be processed will live in the +tokens+ attribute. This list
    # can be converted to a +String+ using +#to_s+ to parse the data with
    # regular expressions (or other text processing mechanisms), if needed.
    # 
    # === +namespace+ Attribute 
    # 
    # The +namespace+ attribute is a {CodeObjects::NamespaceObject namespace object} 
    # which represents the current namespace that the parser is in. For instance:
    # 
    #   module SomeModule
    #     class MyClass
    #       def mymethod; end
    #     end
    #   end
    # 
    # If a handler was to parse the 'class MyClass' statement, it would
    # be necessary to know that it belonged inside the SomeModule module.
    # This is the value that +namespace+ would return when processing such
    # a statement. If the class was then entered and another handler was
    # called on the method, the +namespace+ would be set to the 'MyClass'
    # code object.
    # 
    # === +owner+ Attribute 
    # 
    # The +owner+ attribute is similar to the +namespace+ attribute in that
    # it also follows the scope of the code during parsing. However, a namespace
    # object is loosely defined as a module or class and YARD has the ability
    # to parse beyond module and class blocks (inside methods, for instance),
    # so the +owner+ attribute would not be limited to modules and classes. 
    # 
    # To put this into context, the example from above will be used. If a method
    # handler was added to the mix and decided to parse inside the method body,
    # the +owner+ would be set to the method object but the namespace would remain
    # set to the class. This would allow the developer to process any method
    # definitions set inside a method (def x; def y; 2 end end) by adding them
    # to the correct namespace (the class, not the method).
    # 
    # In summary, the distinction between +namespace+ and +owner+ can be thought
    # of as the difference between first-class Ruby objects (namespaces) and
    # second-class Ruby objects (methods).
    # 
    # === +visibility+ and +scope+ Attributes 
    # 
    # Mainly needed for parsing methods, the +visibility+ and +scope+ attributes
    # refer to the public/protected/private and class/instance values (respectively)
    # of the current parsing position.
    # 
    # == Parsing Blocks in Statements 
    # 
    # In addition to parsing a statement and creating new objects, some
    # handlers may wish to continue parsing the code inside the statement's
    # block (if there is one). In this context, a block means the inside
    # of any statement, be it class definition, module definition, if
    # statement or classic 'Ruby block'. 
    # 
    # For example, a class statement would be "class MyClass" and the block 
    # would be a list of statements including the method definitions inside 
    # the class. For a class handler, the programmer would execute the 
    # {#parse_block} method to continue parsing code inside the block, with 
    # the +namespace+ now pointing to the class object the handler created. 
    # 
    # YARD has the ability to continue into any block: class, module, method, 
    # even if statements. For this reason, the block parsing method must be 
    # invoked explicitly out of efficiency sake.
    # 
    # @see CodeObjects::Base
    # @see CodeObjects::NamespaceObject
    # @see handles
    # @see #namespace
    # @see #owner
    # @see #register
    # @see #parse_block
    #
    class Base 
      attr_accessor :__context__

      # For accessing convenience, eg. "MethodObject" 
      # instead of the full qualified namespace
      include YARD::CodeObjects
      
      # For tokens like TkDEF, TkCLASS, etc.
      include YARD::Parser::RubyToken
      
      class << self
        def clear_subclasses
          @@subclasses = []
        end
        
        def subclasses
          @@subclasses || []
        end

        def inherited(subclass)
          @@subclasses ||= []
          @@subclasses << subclass
        end

        # Declares the statement type which will be processed
        # by this handler. 
        # 
        # A match need not be unique to a handler. Multiple
        # handlers can process the same statement. However,
        # in this case, care should be taken to make sure that
        # {#parse_block} would only be executed by one of
        # the handlers, otherwise the same code will be parsed
        # multiple times and slow YARD down.
        # 
        # @param [Parser::RubyToken, String, Regexp] match
        #   statements that match the declaration will be 
        #   processed by this handler. A {String} match is 
        #   equivalent to a +/\Astring/+ regular expression 
        #   (match from the beginning of the line), and all 
        #   token matches match only the first token of the
        #   statement.
        # 
        def handles(match)
          @handler = match
        end
        
        def handles?(tokens)
          case @handler
          when String
            tokens.first.text == @handler
          when Regexp
            tokens.to_s =~ @handler ? true : false
          else
            @handler == tokens.first.class 
          end
        end
      end
      
      def initialize(source_parser, stmt)
        @parser = source_parser
        @statement = stmt
      end

      # The main handler method called by the parser on a statement
      # that matches the {handles} declaration.
      # 
      # Subclasses should override this method to provide the handling
      # functionality for the class. 
      # 
      # @return [Array<CodeObjects::Base>, CodeObjects::Base, Object]
      #   If this method returns a code object (or a list of them),
      #   they are passed to the +#register+ method which adds basic
      #   attributes. It is not necessary to return any objects and in
      #   some cases you may want to explicitly avoid the returning of
      #   any objects for post-processing by the register method.
      #   
      # @see handles
      # @see #register
      # 
      def process
        raise NotImplementedError, "#{self} did not implement a #process method for handling."
      end
      
      protected
      
      attr_reader :parser, :statement
      attr_accessor :owner, :namespace, :visibility, :scope
      
      def verify_object_loaded(object)
        begin
          [:namespace, :superclass].each do |name|
            next unless object.respond_to?(name)

            pobj = object.send(name)
            load_order!(pobj)
          end
        end
      end
      
      # Do some post processing on a list of code objects. 
      # Adds basic attributes to the list of objects like 
      # the filename, line number, {CodeObjects::Base#dynamic},
      # source code and {CodeObjects::Base#docstring},
      # but only if they don't exist.
      # 
      # @param [Array<CodeObjects::Base>] objects
      #   the list of objects to post-process.
      # 
      # @return [CodeObjects::Base, Array<CodeObjects::Base>]
      #   returns whatever is passed in, for chainability.
      # 
      def register(*objects)
        objects.flatten.each do |object|
          next unless object.is_a?(CodeObjects::Base)
          
          verify_object_loaded(object)
          
          # Yield the object to the calling block because ruby will parse the syntax
          #   
          #     register obj = ClassObject.new {|o| ... }
          # 
          # as the block for #register. We need to make sure this gets to the object.
          yield(object) if block_given? 
          
          # Add file and line number, but for class/modules this is 
          # only done if there is a docstring for this specific definition.
          if (object.is_a?(NamespaceObject) && statement.comments) || !object.is_a?(NamespaceObject)
            object.file = parser.file
            object.line = statement.tokens.first.line_no
          elsif object.is_a?(NamespaceObject) && !statement.comments
            object.file ||= parser.file
            object.line ||= statement.tokens.first.line_no
          end
          
          # Add docstring if there is one.
          object.docstring = statement.comments if statement.comments
          
          # Add source only to non-class non-module objects
          unless object.is_a?(NamespaceObject)
            object.source ||= statement 
          end
          
          # Make it dynamic if it's owner is not it's namespace.
          # This generally means it was defined in a method (or block of some sort)
          object.dynamic = true if owner != namespace
        end
        objects.size == 1 ? objects.first : objects
      end
      
      def parse_block(opts = nil)
        opts = {
          :namespace => nil,
          :scope => :instance,
          :owner => nil
        }.update(opts || {})
        
        if opts[:namespace]
          ns, vis, sc = namespace, visibility, scope
          self.namespace = opts[:namespace]
          self.visibility = :public
          self.scope = opts[:scope]
        end

        self.owner = opts[:owner] ? opts[:owner] : namespace
        parser.parse(statement.block) if statement.block
        
        if opts[:namespace]
          self.namespace = ns
          self.owner = namespace
          self.visibility = vis
          self.scope = sc
        end
      end

      def owner; @parser.owner end
      def owner=(v) @parser.owner=(v) end
      def namespace; @parser.namespace end
      def namespace=(v); @parser.namespace=(v) end
      def visibility; @parser.visibility end
      def visibility=(v); @parser.visibility=(v) end
      def scope; @parser.scope end
      def scope=(v); @parser.scope=(v) end
      
      def load_order!(object)
        return unless parser.load_order_errors
        return unless Proxy === object
        
        retries, context = 0, nil
        callcc {|c| context = c }

        retries += 1 
        raise(Parser::LoadOrderError, context) if retries <= 3

        if !object.is_a?(Proxy)
          object.namespace.children << object 
        elsif !BUILTIN_ALL.include?(object.path)
          log.warn "The #{object.type} #{object.path} has not yet been recognized." 
          log.warn "If this class/method is part of your source tree, this will affect your documentation results." 
          log.warn "You can correct this issue by loading the source file for this object before `#{parser.file}'"
          log.warn 
        end
      end
      
      # The string value of a token. For example, the return value for the symbol :sym 
      # would be :sym. The return value for a string "foo #{bar}" would be the literal 
      # "foo #{bar}" without any interpolation. The return value of the identifier
      # 'test' would be the same value: 'test'. Here is a list of common types and
      # their return values:
      # 
      # @example 
      #   tokval(TokenList.new('"foo"').first) => "foo"
      #   tokval(TokenList.new(':foo').first) => :foo
      #   tokval(TokenList.new('CONSTANT').first, RubyToken::TkId) => "CONSTANT"
      #   tokval(TokenList.new('identifier').first, RubyToken::TkId) => "identifier"
      #   tokval(TokenList.new('3.25').first) => 3.25
      #   tokval(TokenList.new('/xyz/i').first) => /xyz/i
      # 
      # @param [Token] token The token of the class
      # 
      # @param [Array<Class<Token>>, Symbol] accepted_types
      #   The allowed token types that this token can be. Defaults to [{TkVal}].
      #   A list of types would be, for example, [{TkSTRING}, {TkSYMBOL}], to return
      #   the token's value if it is either of those types. If +TkVal+ is accepted, 
      #   +TkNode+ is also accepted.
      # 
      #   Certain symbol keys are allowed to specify multiple types in one fell swoop.
      #   These symbols are:
      #     :string       => +TkSTRING+, +TkDSTRING+, +TkDXSTRING+ and +TkXSTRING+
      #     :attr         => +TkSYMBOL+ and +TkSTRING+
      #     :identifier   => +TkIDENTIFIER, +TkFID+ and +TkGVAR+.
      #     :number       => +TkFLOAT+, +TkINTEGER+
      # 
      # @return [Object] if the token is one of the accepted types, in its real value form.
      #   It should be noted that identifiers and constants are kept in String form.
      # @return [nil] if the token is not any of the specified accepted types
      def tokval(token, *accepted_types)
        accepted_types = [TkVal] if accepted_types.empty?
        accepted_types.push(TkNode) if accepted_types.include? TkVal
        
        if accepted_types.include?(:attr)
          accepted_types.push(TkSTRING, TkSYMBOL)
        end

        if accepted_types.include?(:string)
          accepted_types.push(TkSTRING, TkDSTRING, TkXSTRING, TkDXSTRING)
        end
        
        if accepted_types.include?(:identifier)
          accepted_types.push(TkIDENTIFIER, TkFID, TkGVAR)
        end

        if accepted_types.include?(:number)
          accepted_types.push(TkFLOAT, TkINTEGER)
        end
        
        return unless accepted_types.any? {|t| t === token }
        
        case token
        when TkSTRING, TkDSTRING, TkXSTRING, TkDXSTRING 
          token.text[1..-2]
        when TkSYMBOL
          token.text[1..-1].to_sym
        when TkFLOAT
          token.text.to_f
        when TkINTEGER
          token.text.to_i
        when TkREGEXP
          token.text =~ /\A\/(.+)\/([^\/])\Z/
          Regexp.new($1, $2)
        when TkTRUE
          true
        when TkFALSE
          false
        when TkNIL
          nil
        else
          token.text
        end
      end
      
      # Returns a list of symbols or string values from a statement. 
      # The list must be a valid comma delimited list, and values 
      # will only be returned to the end of the list only.
      # 
      # Example:
      #   attr_accessor :a, 'b', :c, :d => ['a', 'b', 'c', 'd']
      #   attr_accessor 'a', UNACCEPTED_TYPE, 'c' => ['a', 'c'] 
      # 
      # The tokval list of a {TokenList} of the above
      # code would be the {#tokval} value of :a, 'b',
      # :c and :d.
      # 
      # It should also be noted that this function stops immediately at
      # any ruby keyword encountered:
      #   "attr_accessor :a, :b, :c if x == 5"  => ['a', 'b', 'c']
      # 
      # @param [TokenList] tokenlist The list of tokens to process.
      # @param [Array<Class<Token>>] accepted_types passed to {#tokval}
      # @return [Array<String>] the list of tokvalues in the list.
      # @return [Array<EMPTY>] if there are no symbols or Strings in the list 
      # @see #tokval
      def tokval_list(tokenlist, *accepted_types)
        return [] unless tokenlist
        out = [[]]
        parencount, beforeparen = 0, 0
        needcomma = false
        seen_comma = true
        tokenlist.each do |token|
          tokval = tokval(token, *accepted_types)
          parencond = !out.last.empty? && tokval != nil
          #puts "#{seen_comma.inspect} #{parencount} #{token.class.class_name} #{out.inspect}"
          case token
          when TkCOMMA
            if parencount == 0
              out << [] unless out.last.empty?
              needcomma = false
              seen_comma = true
            else
              out.last << token.text if parencond
            end
          when TkLPAREN
            if seen_comma
              beforeparen += 1
            else
              parencount += 1
              out.last << token.text if parencond
            end
          when TkRPAREN
            if beforeparen > 0
              beforeparen -= 1
            else
              out.last << token.text if parencount > 0 && tokval != nil
              parencount -= 1
            end
          when TkLBRACE, TkLBRACK, TkDO
            parencount += 1 
            out.last << token.text if tokval != nil
          when TkRBRACE, TkRBRACK, TkEND
            out.last << token.text if tokval != nil
            parencount -= 1
          else
            break if TkKW === token && ![TkTRUE, TkFALSE, TkSUPER, TkSELF, TkNIL].include?(token.class)
            
            seen_comma = false unless TkWhitespace === token
            if parencount == 0
              next if needcomma 
              next if TkWhitespace === token
              if tokval != nil
                out.last << tokval
              else
                out.last.clear
                needcomma = true
              end 
            elsif parencond
              needcomma = true
              out.last << token.text
            end
          end

          if beforeparen == 0 && parencount < 0
            break
          end
        end
        # Flatten any single element lists
        out.map {|e| e.empty? ? nil : (e.size == 1 ? e.pop : e.flatten.join) }.compact
      end
    end
  end
end