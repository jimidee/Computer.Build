require 'computer_build/vhdl'
require 'computer_build/state_machine'

class Computer
  def self.Build(name)
    instance = Computer.new(name)
    yield(instance)
    instance.generate
  end
  
  attr_writer :address_width
  
  def initialize(name)
    @name = name
    @instructions = []
  end
  
  def instruction(name)
    inst = Instruction.new(name)
    yield(inst)
    @instructions << inst
  end
  
  def generate
    states = make_states(@instructions).merge(static_states)
    opcodes = make_opcodes(@instructions)
    control_signals = states.values.map(&:control_signals).flatten.uniq

    control = state_machine("control") do |m|
      m.input :reset, VHDL::STD_LOGIC
      m.input :system_bus, VHDL::STD_LOGIC_VECTOR(7..0)
      m.signal :opcode,
        VHDL::STD_LOGIC_VECTOR((opcodes.values.first.length - 1)..0)
      m.reset do |r|
        r.goto :fetch
        control_signals.each do |sig|
          r.low sig.to_sym
        end
      end

      states.each do |name, state|
        m.state(name) do |s|
          control_signals.each do |sig|
            s.assign sig, state.control_signals.include?(sig) ? '1' : '0'
          end

          if name == 'fetch'
            s.assign :opcode, "2 downto 0", :system_bus, "7 downto 5"
          end
        end

        m.transition :from => name, :to => state.next if state.next
      end

      # instruction decode
      opcodes.each do |instruction, opcode|
        m.transition :from => :decode, :to => instruction.name+"_0",
          :on => equal(:opcode, opcode)
      end
    end

    main = entity("main") do |e|
      e.port :in, :clock, VHDL::STD_LOGIC
      e.port :in, :reset, VHDL::STD_LOGIC
      e.port :out, :bus_inspection, VHDL::STD_LOGIC_VECTOR(7..0)

      e.signal :system_bus, VHDL::STD_LOGIC_VECTOR(7..0)
    end
    
    control.generate
  end
  
  # inner classes
  
  class Instruction
    attr_reader :name, :steps

    def initialize(name)
      @name = name
      @steps = []
    end
    
    def move(target, source)
      @steps << RTL.new(target, source)
    end

    def microcode
      steps.map &:to_microcode
    end
  end
  
  class ALUOperation
    attr_reader :op, :operands

    def initialize(op, *operands)
      @op = op
      @operands = operands
    end
  end

  private

  class RTL
    def initialize(target, source)
      @target = target
      @source = source
    end
    
    def to_microcode
      if @source.is_a? Fixnum
        return MicrocodeState.new do |state|
          state.control_signals = "wr_#{@target}"
          state.constant_value = @source
        end
      elsif @source.is_a? Symbol
        return MicrocodeState.new do |state|
          state.control_signals = ["wr_#{@target}", "rd_#{@source}"]
        end
      elsif @source.is_a? ALUOperation
        steps = []
        steps << MicrocodeState.new do |state|
          state.control_signals = ["rd_#{@source.operands.first}", "wr_alu_a"]
          state.alu_op = @source.op
        end

        if @source.operands.length == 2
          steps << MicrocodeState.new do |state|
            state.control_signals = ["wr_alu_b"]
            if @source.operands.last.is_a? Fixnum
              state.constant_value = @source.operands.last
            else
              state.control_signals << "rd_#{@source.operands.last}"
            end
          end
        end

        steps << MicrocodeState.new do |state|
          state.control_signals = ["rd_alu", "wr_#{@target}"]
          state.alu_op = @source.op
        end
        return steps
      end
    end
  end

  class MicrocodeState
    attr_accessor :control_signals, :alu_op, :constant_value, :next
    def initialize(&blk)
      yield(self) if blk
    end
  end

  def make_states(instructions)
    states = {}
    instructions.each do |instr|
      steps = instr.microcode.flatten
      steps.each_with_index do |step, index|
        if index + 1 < steps.length
          step.next = instr.name+"_"+(index+1).to_s
        else
          step.next = :fetch
        end
        states[instr.name+"_"+index.to_s] = step
      end
    end

    return states
  end

  def make_opcodes(instructions)
    bits = (Math.log(instructions.length)/Math.log(2)).ceil
    opcodes = {}
    instructions.each_with_index do |instruction, idx|
      bin_string = idx.to_s(2)
      bin_string = ("0" * (bits - bin_string.length)) + bin_string
      opcodes[instruction] = bin_string
    end
    return opcodes
  end

  def static_states
    states = {}
    states['fetch'] = MicrocodeState.new do |s|
      s.control_signals = ['rd_pc', 'wr_MA']
      s.next = 'store_instruction'
    end

    states['store_instruction'] = MicrocodeState.new do |s|
      s.control_signals = ['rd_MD', 'wr_IR']
      s.next = 'decode'
    end

    states['decode'] = MicrocodeState.new do |s|
      s.control_signals = []
    end

    return states
  end
end

def complement(value)
  Computer::ALUOperation.new(:complement, value)
end

def add(operand1, operand2)
  Computer::ALUOperation.new(:add, operand1, operand2)
end

def subtract(operand1, operand2)
  Computer::ALUOperation.new(:subtract, operand1, operand2)
end
