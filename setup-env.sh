#!/bin/bash 
BASE_DIR_NAME=$(dirname `which $0`)

GEM_HOME=${BASE_DIR_NAME}/.gems
GEM_PATH=${BASE_DIR_NAME}/.gems
PATH=${BASE_DIR_NAME}/ruby/bin:${BASE_DIR_NAME}/./bin:$PATH
RUBYLIB=${BASE_DIR_NAME}/OpenStudio/Ruby
RUBY_DLL_PATH=${BASE_DIR_NAME}/OpenStudio/Ruby

# Remove if exists
if [ -f env.sh ]; then
  rm env.sh
fi

echo "export GEM_HOME=\"${GEM_HOME}\"" >> env.sh
echo "export GEM_PATH=\"${GEM_PATH}\"" >> env.sh
echo "export PATH=\"${PATH}\"" >> env.sh
echo "export RUBYLIB=\"${RUBYLIB}\"" >> env.sh
echo "export RUBY_DLL_PATH=\"${RUBY_DLL_PATH}\"" >> env.sh


