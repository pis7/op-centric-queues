#include "VTop.h"
#include "verilated.h"

int main(int argc, char **argv) {

  // create context
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};

  // enable tracing
  contextp->traceEverOn( true );

  // obtain arguments
  contextp->commandArgs( argc, argv );

  // create new top module
  VTop* top = new VTop;

  // simulation loop
  while (!contextp->gotFinish()) {
      top->eval();
      contextp->timeInc(1);
  }

  // terminate top module
  top->final();

  // dump trace for coverage
  Verilated::mkdir("logs");
  contextp->coveragep()->write("logs/coverage.dat");
  
  return 0;
}
