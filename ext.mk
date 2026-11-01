HAS_SUBMODULES = 1

export ADN_MEMSS=$(CURDIR)
export REPO_NAME_EXP=ADN_MEMSS

export ADN_COMMON=$(REPO_ROOT)/submodule/adn_common
export MICRON_DDR3=$(REPO_ROOT)/submodule/micron_ddr3

.PHONY: compile_all_submodules
compile_all_submodules:
	@make -s compile_submodule SUB=adn_common
	@make -s compile_micron_ddr3

SG := -d sg125
DN := -d den8192Mb

.PHONY: compile_micron_ddr3
compile_micron_ddr3:
	@cd $(BUILD_DIR) && $(XVLOG) -sv $(SG) $(DN) -f $(MICRON_DDR3)/reuse.f -log $(LOG_DIR)/xvlog_micron_ddr3_$(shell date +%Y%m%d_%H%M%S).log $(O_EW);
