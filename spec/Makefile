.PHONY: test unit check repl

unit:
	quint test ./tests.qnt

repl:
	echo "init\n step\n step\n step" | quint -r main.qnt::main 

check:
	quint typecheck main.qnt

test: check repl unit