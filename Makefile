# tnx to mamalala
# Changelog
# Changed the variables to include the header file directory
# Added global var for the XTENSA tool root
#
# This make file still needs some work.
#
#
# Output directors to store intermediate compiled files
# relative to the project directory
BUILD_BASE	= build
FW_BASE		= firmware

# Base directory for the compiler
XTENSA_TOOLS_ROOT ?= /opt/xtensa-lx106-elf/bin

# base directory of the ESP8266 SDK package, absolute
SDK_BASE	?= /opt/Espressif/ESP8266_SDK

#Extra Tensilica includes from the ESS VM
SDK_EXTRA_INCLUDES ?= $(addsuffix  /include,$(SDK_BASE))

#Esptool.py path and port
ESPTOOL		?= esptool.py
ESPPORT		?= /dev/ttyUSB0

# name for the target project
TARGET		= httpd

# which modules (subdirectories) of the project to include in compiling
MODULES		= driver user
EXTRA_INCDIR	= include \
		. \
		lib/heatshrink/ \
		$(SDK_EXTRA_INCLUDES)

# libraries used in this project, mainly provided by the SDK
LIBS		= c gcc hal phy pp net80211 lwip wpa main

# compiler flags using during compilation of source files
CFLAGS		= -Os -ggdb -std=c99 -Werror -Wpointer-arith -Wundef -Wall -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals  -D__ets__ -DICACHE_FLASH

# linker flags used to generate the main object file
LDFLAGS		= -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static

# linker script used for the above linkier step
LD_SCRIPT	= eagle.app.v6.ld

# various paths from the SDK used in this project
SDK_LIBDIR	= lib
SDK_LDDIR	= ld
SDK_INCDIR	= include

# we create two different files for uploading into the flash
# these are the names and options to generate them
FW_FILE_1	= 0x00000
FW_FILE_1_ARGS	= -bo $@ -bs .text -bs .data -bs .rodata -bc -ec
FW_FILE_2	= 0x40000
FW_FILE_2_ARGS	= -es .irom0.text $@ -ec
FW_FILE_3	= webpages.espfs

# select which tools to use as compiler, librarian and linker
CC		:= $(XTENSA_TOOLS_ROOT)/xtensa-lx106-elf-gcc
AR		:= $(XTENSA_TOOLS_ROOT)/xtensa-lx106-elf-ar
LD		:= $(XTENSA_TOOLS_ROOT)/xtensa-lx106-elf-gcc



####
#### no user configurable options below here
####
FW_TOOL		?= /usr/bin/esptool
SRC_DIR		:= $(MODULES)
BUILD_DIR	:= $(addprefix $(BUILD_BASE)/,$(MODULES))

SDK_LIBDIR	:= $(addprefix $(SDK_BASE)/,$(SDK_LIBDIR))
SDK_INCDIR_OPT	:= $(addprefix -I$(SDK_BASE)/,$(SDK_INCDIR))

SRC		:= $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.c))
OBJ		:= $(patsubst %.c,$(BUILD_BASE)/%.o,$(SRC))
LIBS		:= $(addprefix -l,$(LIBS))
APP_AR		:= $(addprefix $(BUILD_BASE)/,$(TARGET)_app.a)
TARGET_OUT	:= $(addprefix $(BUILD_BASE)/,$(TARGET).out)

LD_SCRIPT	:= $(addprefix -T$(SDK_BASE)/$(SDK_LDDIR)/,$(LD_SCRIPT))

INCDIR_OPT	:= $(addprefix -I,$(SRC_DIR))
EXTRA_INCDIR_OPT	:= $(addprefix -I,$(EXTRA_INCDIR))
MODULE_INCDIR_OPT	:= $(addsuffix /include,$(INCDIR))

FW_FILE_1	:= $(addprefix $(FW_BASE)/,$(FW_FILE_1).bin)
FW_FILE_2	:= $(addprefix $(FW_BASE)/,$(FW_FILE_2).bin)

V ?= $(VERBOSE)
ifeq ("$(V)","1")
Q :=
vecho := @true
else
Q := @
vecho := @echo
endif

vpath %.c $(SRC_DIR)

define compile-objects
$1/%.o: %.c
	$(vecho) "CC $$<"
	$(Q) $(CC) $(INCDIR_OPT) $(MODULE_INCDIR_OPT) $(EXTRA_INCDIR_OPT) $(SDK_INCDIR_OPT) $(CFLAGS)  -c $$< -o $$@
endef

.PHONY: all checkdirs clean

all: checkdirs $(TARGET_OUT) $(FW_FILE_1) $(FW_FILE_2) $(FW_FILE_3) TAGS

$(FW_FILE_1): $(TARGET_OUT) firmware
	$(vecho) "FW $@"
	$(Q) $(FW_TOOL) -eo $(TARGET_OUT) $(FW_FILE_1_ARGS)

$(FW_FILE_2): $(TARGET_OUT) firmware
	$(vecho) "FW $@"
	$(Q) $(FW_TOOL) -eo $(TARGET_OUT) $(FW_FILE_2_ARGS)

$(TARGET_OUT): $(APP_AR)
	$(vecho) "LD $@"
	$(Q) $(LD) -L$(SDK_LIBDIR) $(LD_SCRIPT) $(LDFLAGS) -Wl,--start-group $(LIBS) $(APP_AR) -Wl,--end-group -o $@

$(APP_AR): $(OBJ)
	$(vecho) "AR $@"
	$(Q) $(AR) cru $@ $^

checkdirs: $(BUILD_DIR) $(FW_BASE)

$(BUILD_DIR):
	$(Q) mkdir -p $@

firmware:
	$(Q) mkdir -p $@

flash1: $(FW_FILE_1)
	-$(ESPTOOL) --port $(ESPPORT) write_flash 0x00000 $<

flash2: $(FW_FILE_2)
	-$(ESPTOOL) --port $(ESPPORT) write_flash 0x40000 $<

flash: $(FW_FILE_1) $(FW_FILE_2) $(FW_FILE_3)
	-$(ESPTOOL) --port $(ESPPORT) write_flash 0x00000 $(FW_FILE_1) 0x40000 $(FW_FILE_2) 0x12000 $(FW_FILE_3)

webpages.espfs: html/ mkespfsimage/mkespfsimage
	$(vecho) "webpages: $@"
	$(Q) cd html; find | ../mkespfsimage/mkespfsimage  > ../webpages.espfs; cd ..
	$(Q) if [ $$(stat -c '%s' webpages.espfs) -gt $$(( 0x2E000 )) ]; then echo "ERROR: webpages.espfs too big!"; false; fi

mkespfsimage/mkespfsimage: mkespfsimage/
	make -C mkespfsimage

htmlflash: webpages.espfs
	-$(ESPTOOL) --port $(ESPPORT) write_flash 0x12000 webpages.espfs

TAGS: $(FW_FILE_1) $(FW_FILE_2) $(FW_FILE_3)
	$(vecho) "TAGS"
	$(Q) etags -R $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) 2>/dev/null

clean:
	$(Q) rm -f $(APP_AR)
	$(Q) rm -f $(TARGET_OUT)
	$(Q) find $(BUILD_BASE) -type f | xargs rm -f


	$(Q) rm -f $(FW_FILE_1)
	$(Q) rm -f $(FW_FILE_2)
	$(Q) rm -f $(FW_FILE_3)
	$(Q) rm -rf $(FW_BASE)

$(foreach bdir,$(BUILD_DIR),$(eval $(call compile-objects,$(bdir))))
