<?php

namespace ComputerBuild\Vhdl;

use ComputerBuild\Filesystem\GeneratedOutput;

class Equal extends InlineStatement
{
    protected $target;
    protected $expression;

    public function __construct($target, $expression)
    {
        $this->target = $target;
        $this->expression = $expression;
    }

    /**
     * goal of generate:
     * syntactically correct implementation
     */
    public function generate()
    {
        return $this->target." = ".$this->quoted($this->expression);
    }
}
