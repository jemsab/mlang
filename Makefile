SOURCE_DIR_2015=ir-calcul/sources2015m_4_6/
SOURCE_DIR_2016=ir-calcul/sources2016m_4_5/
SOURCE_DIR_2017=ir-calcul/sources2017m_6_10/
SOURCE_DIR_2018=ir-calcul/sources2018m_6_7/

SOURCE_FILES?=$(shell find $(SOURCE_DIR_2018) -name "*.m")

ifeq ($(OPTIMIZE), 1)
    OPTIMIZE_FLAG=-O
else
    OPTIMIZE_FLAG=
endif

default: build

deps:
	opam install ppx_deriving ANSITerminal re ocamlgraph dune menhir \
	cmdliner dune-build-info visitors parmap num ocamlformat
	git submodule update --init --recursive

format:
	dune build @fmt --auto-promote | true

build: #format
	dune build

MLANG= dune exec src/main.exe -- \
	--display_time --debug \
	--mpp_file=2018.mpp \
	$(OPTIMIZE_FLAG) \
	--mpp_function=compute_double_liquidation_pvro

# use: TEST_FILE=bla make test
test: build
	$(MLANG) --run_test=$(TEST_FILE) $(SOURCE_FILES)

# use: TESTS_DIR=bla make test
tests: build
	$(MLANG) --run_all_tests=$(TESTS_DIR) $(SOURCE_FILES)

interpreter:
	$(MLANG) --backend interpreter --function_spec interpreter.m_spec $(SOURCE_FILES)

doc:
	dune build @doc
	ln -s _build/default/_doc/_html/index.html doc.html
