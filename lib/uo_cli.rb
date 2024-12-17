#!/usr/bin/ ruby

# *********************************************************************************
# URBANopt (tm), Copyright (c) Alliance for Sustainable Energy, LLC.
# See also https://github.com/urbanopt/urbanopt-cli/blob/develop/LICENSE.md
# *********************************************************************************

require 'uo_cli/version'
require 'optimist'
require 'urbanopt/geojson'
require 'urbanopt/scenario'
require 'urbanopt/reopt'
require 'urbanopt/reopt_scenario'
require 'urbanopt/rnm'
require 'csv'
require 'fileutils'
require 'json'
require 'openssl'
require 'open3'
require 'yaml'

module URBANopt
  module CLI
    class UrbanOptCLI
      COMMAND_MAP = {
        'create' => 'Make new things - project directory or files',
        'install_python' => 'Install python and other dependencies to run OpenDSS, DISCO, GMT analysis',
        'update' => 'Update files in an existing URBANopt project',
        'run' => 'Use files in your directory to simulate district energy use',
        'process' => 'Post-process URBANopt simulations for additional insights',
        'visualize' => 'Visualize and compare results for features and scenarios',
        'validate' => 'Validate results with custom rules',
        'opendss' => 'Run OpenDSS simulation',
        'disco' => 'Run DISCO analysis',
        'rnm' => 'Run RNM simulation',
        'delete' => 'Delete simulations for a specified scenario',
        'des_params' => 'Make a DES system parameters config file',
        'des_create' => 'Create a Modelica model',
        'des_run' => 'Run a Modelica DES model',
        'des_process' => 'Post-Process a Modelica DES model for REopt Financial Analysis',
        'ghe_size' => 'Run a Ground Heat Exchanger model for sizing',
      }.freeze

      def initialize
        @subopts = nil
        @command = nil
        @mainopts = Optimist.options do
          version VERSION
          banner "\nURBANopt CLI version: #{version}"
          banner "\nUsage:"
          banner "  uo [options] [<command> [suboptions]]\n \n"
          banner 'Options:'
          opt :version, 'Print version and exit'  ## add this here or it goes to bottom of help
          opt :help, 'Show this help message'     ## add this here or it goes to bottom of help
          # opt :no_pager, "Disable paging"
          stop_on COMMAND_MAP.keys
          banner "\nCommands:"
          COMMAND_MAP.each { |cmd, desc| banner format('  %-14s %s', cmd, desc) }
          banner "\nFor help with a specific command: uo <command> --help"
          banner "\nAdditional config options can be set with the 'runner.conf' file inside your project folder"
          banner 'Fewer warnings are presented when using full paths and the user is not inside the project folder'
        end
        return if ARGV.empty?

        @command = ARGV.shift
        begin
          send("opt_#{@command}") ## dispatch to command handling method
        rescue NoMethodError
          abort('Invalid command, please run uo --help for a list of available commands')
        rescue StandardError => e
          puts "\nERROR: #{e.message}"
        end
      end

      # Define creation commands
      def opt_create
        @subopts = Optimist.options do
          banner "\nURBANopt create:\n \n"

          opt :project_folder, "\nCreate project directory in your current folder. Name the directory\n" \
          "Add additional tags to specify the method for creating geometry, or use the default urban geometry creation method to create building geometry from geojson coordinates with core and perimeter zoning\n" \
          'Example: uo create --project-folder urbanopt_example_project', type: String, short: :p

          opt :create_bar, "\nCreate building geometry and add space types using the create bar from building type ratios measure\n" \
          "Refer to https://docs.urbanopt.net/ for more details about the workflow\n" \
          "Used with --project-folder\n" \
          "Example: uo create --project-folder urbanopt_example_project --create-bar\n", short: :c

          opt :floorspace, "\nCreate building geometry and add space types from a floorspace.js file\n" \
          "Refer to https://docs.urbanopt.net/ for more details about the workflow\n" \
          "Used with --project-folder\n" \
          "Example: uo create --project-folder urbanopt_example_project --floorspace\n", short: :f

          opt :combined, "\nCreate project directory that supports running combined residential and commercial workflows\n" \
          "This functionality has not been exhaustively tested and currently supports the Single-Family Detached building type and the Baseline Scenario only\n" \
          "Used with --project-folder\n" \
          "Example: uo create --project-folder urbanopt_example_project --combined\n", short: :d

          opt :electric, "\nCreate default project with FeatureFile containing electrical network, used for OpenDSS analysis\n" \
          'Example: uo create --project-folder urbanopt_example_project --electric', short: :l

          opt :disco, "\nCreate default project with FeatureFile containing electrical network, and scenarios for DISCO cost upgrade analysis\n"\
          'Example: uo create --project-folder urbanopt_example_project --disco', short: :a

          opt :streets, "\nCreate default project with FeatureFile containing streets, used for RNM analysis\n" \
          'Example: uo create --project-folder urbanopt_example_project --streets', short: :t

          opt :photovoltaic, "\nCreate default project with FeatureFile containing community photovoltaic for the district and ground-mount photovoltaic associated with buildings, used for REopt analysis \n" \
          'Example: uo create --project-folder urbanopt_example_project --photovoltaic', short: :v

          opt :ghe, "\nCreate default project with FeatureFile containing Ground Heat Exchanger Network\n" \
          'Example: uo create --project-folder urbanopt_example_project --ghe', short: :g

          opt :class_coincident, "\nCreate default class project with buildings that have coincident schedules \n" \
          "Refer to https://docs.urbanopt.net/ for more details about the class project \n" \
          "Used with --project-folder\n" \
          "Example: uo create --project-folder urbanopt_example_project --class-coincident\n", short: :C

          opt :class_diverse, "\nCreate default class project with buildings that have diverse schedules \n" \
          "Refer to https://docs.urbanopt.net/ for more details about the class project \n" \
          "Used with --project-folder\n" \
          "Example: uo create --project-folder urbanopt_example_project --class-diverse\n", short: :D

          opt :empty, "\nUse with --project-folder argument to create an empty project folder\n" \
          "Then add your own Feature file in the project directory you created,\n" \
          "add Weather files in the weather folder and add OpenStudio models of Features\n" \
          "in the Feature File, if any, in the osm_building folder\n" \
          "Example: uo create --empty --project-folder urbanopt_example_project\n", short: :e

          opt :overwrite, "\nUse with --project-folder argument to overwrite existing project folder and replace with new project folder.\n" \
          "May be combined with --empty as well to overwrite existing project folder and replace with new empty project folder.\n" \
          "Example: uo create --overwrite --empty --project-folder urbanopt_project_folder_I_want_destroyed\n", short: :o

          opt :scenario_file, "\nAutomatically create a ScenarioFile containing the features in FeatureFile for each scenario\n" \
          "Provide the FeatureFile used to create the ScenarioFile\n" \
          "Example: uo create --scenario-file example_project.json\n", type: String, short: :s

          opt :single_feature, "\nCreate a ScenarioFile with only a single feature\n" \
          "Use the FeatureID from your FeatureFile\n" \
          "Requires 'scenario-file' also be specified, to say which FeatureFile will create the ScenarioFile\n" \
          "Example: uo create --single-feature 2 --scenario-file example_project.json\n", type: String, short: :i

          opt :reopt_scenario_file, "\nCreate a ScenarioFile that includes a column defining the REopt assumptions file\n" \
          "Specify the existing ScenarioFile that you want to extend with REopt functionality\n" \
          "Example: uo create --reopt-scenario-file baseline_scenario.csv\n", type: String, short: :r
        end
      end

      # Define commands to install python
      def opt_install_python
        @subopts = Optimist.options do
          banner "\nURBANopt install_python:\n \n"

          opt :verbose, "\Verbose output \n" \
          'Example: uo install_python --verbose'
        end
      end

      # Update project
      def opt_update
        @subopts = Optimist.options do
          banner "\nURBANopt update:\n \n"

          opt :existing_project_folder, "\Specify existing project folder name to update files \n" \
          'Example: uo update --existing-project-folder urbanopt_example_project --new-project-directory path/to/new_urbanopt_example_project', type: String, short: :e

          opt :new_project_directory, "\Specify location for updated URBANopt project. \n" \
          'Example: uo update --existing-project-folder urbanopt_example_project --new-project-directory path/to/new_urbanopt_example_project', type: String, short: :n
        end
      end

      # Define running commands
      def opt_run
        @subopts = Optimist.options do
          banner "\nURBANopt run:\n \n"

          opt :scenario, "\nRun URBANopt simulations for <scenario>\n" \
          "Requires --feature also be specified\n" \
          'Example: uo run --scenario baseline_scenario-2.csv --feature example_project.json', default: 'baseline_scenario.csv', required: true, short: :s

          opt :feature, "\nRun URBANopt simulations according to <featurefile>\n" \
          "Requires --scenario also be specified\n" \
          'Example: uo run --scenario baseline_scenario.csv --feature example_project.json', default: 'example_project.json', required: true, short: :f

          opt :num_parallel, "\nOPTIONAL: Run URBANopt simulations in parallel using <num_parallel> cores\n" \
          "Adjusts value of 'num_parallel' in the 'runner.conf' file\n" \
          "Example: uo run --num-parallel 2\n", type: Integer, short: :n
        end
      end

      # Define opendss commands
      def opt_opendss
        @subopts = Optimist.options do
          banner "\nURBANopt opendss:\n\n"

          opt :scenario, "\nRun OpenDSS simulations for <scenario>\n" \
          "Requires --feature also be specified\n" \
          'Example: uo opendss --scenario baseline_scenario-2.csv --feature example_project.json', default: 'baseline_scenario.csv', short: :s

          opt :feature, "\nRun OpenDSS simulations according to <featurefile>\n" \
          "Requires --scenario also be specified\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json', default: 'example_project_with_electric_network.json', short: :f

          opt :equipment, "\nRun OpenDSS simulations using <equipmentfile>. If not specified, the extended_catalog.json from urbanopt-ditto-reader will be used.\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json', type: String, short: :e

          opt :timestep, "\nNumber of minutes per timestep in the OpenDSS simulation.\n" \
          "Optional, defaults to analog of simulation timestep set in the FeatureFile\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --timestep 15', type: Integer, short: :t

          opt :start_date, "\nBeginning date for OpenDSS analysis specified in YYYY\\MM\\DD format. \n" \
          "Optional, defaults to beginning of simulation date\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --start-date 2017/01/15', type: String, short: :a

          opt :start_time, "\nBeginning time for OpenDSS analysis specified in hh:mm:ss format. \n" \
          "Optional, defaults to 00:00:00 of start_date if specified, otherwise beginning of simulation time\n" \
          "Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --start-time 01:00:00\n", type: String, short: :b

          opt :end_date, "\nEnd date for OpenDSS analysis specified in YYYY\\MM\\DD format.\n" \
          "Optional, defaults to end of simulation date\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --end-date 2017/01/16', type: String, short: :z

          opt :end_time, "\nEnd time for OpenDSS analysis specified in hh:mm:ss format. \n" \
          "Optional, defaults to 23:00:00 of end_date if specified, otherwise end of simulation time is used. \n" \
          "Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --end-time 01:00:00\n", type: String, short: :y

          opt :upgrade, "\nUpgrade undersized transformers\n" \
          "Optional, defaults to false if not provided\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --upgrade', short: :u

          opt :reopt, "\nRun with additional REopt functionality.\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --reopt', short: :r

          opt :rnm, "\nUse RNM-generated DSS files in this analysis\n" \
          'Example: uo opendss --scenario baseline_scenario.csv --feature example_project.json --rnm', short: :m

          opt :config, "\nRun OpenDSS using a json config file to specify the above settings.\n" \
          'Example: uo opendss --config path/to/config.json', type: String, short: :c
        end
      end

      # Define DISCO commands
      def opt_disco
        @subopts = Optimist.options do
          banner "\nURBANopt disco:\n\n"

          opt :scenario, "\nRun DISCO simulations for <scenario>\n" \
          "Requires --feature also be specified\n" \
          'Example: uo disco --scenario baseline_scenario-2.csv --feature example_project.json', default: 'baseline_scenario.csv', short: :s

          opt :feature, "\nRun DISCO simulations according to <featurefile>\n" \
          "Requires --scenario also be specified\n" \
          'Example: uo disco --scenario baseline_scenario.csv --feature example_project.json', default: 'example_project_with_electric_network.json', short: :f

          opt :cost_database, "\nSpecify cost database for electric equipment upgrade\n" \
          'Example: uo disco --scenario baseline_scenario.csv --feature example_project.json --cost_database cost_database.xlsx', default: 'cost_database.xlsx', short: :c

          opt :technical_catalog, "\nSpecify technical catalog for thermal upgrade\n" \
          'Example: uo disco --scenario baseline_scenario.csv --feature example_project.json --technical_catalog technical_catalog.json', short: :t
        end
      end

      # Define RNM commands
      def opt_rnm
        @subopts = Optimist.options do
          banner "\nURBANopt rnm:\n\n"

          opt :scenario, "\nRun RNM simulation for <scenario>. Scenario must be run and post-processed prior to calling the rnm command.\n" \
          "Requires --feature also be specified\n" \
          'Example: uo rnm --scenario baseline_scenario-2.csv --feature example_project.json', default: 'baseline_scenario.csv', required: true, short: :s

          opt :feature, "\nRun RNM simulation according to <featurefile>\n" \
          "Requires --scenario also be specified\n" \
          'Example: uo rnm --scenario baseline_scenario.csv --feature example_project.json', default: 'example_project_with_streets.json', required: true, short: :f

          opt :reopt, "\nInclude processed REopt optimization results in the simulation.\n" \
          'Example: uo rnm --scenario baseline_scenario.csv --feature example_project.json --reopt', short: :r

          opt :extended_catalog, "\nUse this option to specify the extended electrical catalog path.\n" \
          'If this option is not included, the default catalog will be used', type: String, short: :c

          opt :average_peak_catalog, "\nUse this option to specify the average peak catalog path.\n" \
          'If this option is not included, the default catalog will be used', type: String, short: :a

          opt :opendss, "\n If this option is specified, an OpenDSS-compatible electrical database will be created \n" \
          'Example: uo rnm --scenario baseline_scenario.csv --feature example_project_with_streets.json --opendss', short: :o
        end
      end

      # Define post-processing commands
      def opt_process
        @subopts = Optimist.options do
          banner "\nURBANopt process:\n \n"

          opt :default, "\nStandard post-processing for your scenario", short: :d

          opt :opendss, "\nPost-process with OpenDSS", short: :o

          opt :disco, "\nPost-process with DISCO", short: :i

          opt :reopt_scenario, "\nOptimize for entire scenario with REopt.  Used with the --reopt-scenario-assumptions-file to specify the assumptions to use.\n" \
          'Example: uo process --reopt-scenario', short: :r

          opt :reopt_feature, "\nOptimize for each building individually with REopt\n" \
          'Example: uo process --reopt-feature', short: :e

          opt :reopt_resilience, "\nInclude resilience reporting in REopt optimization\n" \
          'Example: uo process --reopt-scenario --reopt-resilience', short: :p

          opt :reopt_keep_existing, "\nKeep existing reopt feature optimizations instead of rerunning them to avoid rate limit issues.\n" \
          'Example: uo process --reopt-feature --reopt-keep-existing', short: :k

          opt :with_database, "\nInclude a sql database output of post-processed results\n" \
          'Example: uo process --default --with-database', short: :w

          opt :reopt_scenario_assumptions_file, "\nPath to the scenario REopt assumptions JSON file you want to use. Use with the --reopt-scenario post-processor.\n" \
          'If not specified, the reopt/base_assumptions.json file will be used', type: String, short: :a

          opt :reopt_ghp, "\nAnalyze LCCA for GHP. This command is run with --reopt_ghp_assumptions_file (optional), --system_parameter (required), --modelica_model (required).", short: :t

          opt :reopt_ghp_assumptions_file, "\nPath to the GHP REopt assumptions JSON file you want to use. Use with the --reopt-ghp post-processor.\n" \
          'If not specified, the reopt_ghp/ghp_assumptions.json file will be used', type: String, short: :b

          opt :system_parameter, "\nSystem Parameter file used for GHP sizing analysis. This is a required argument for the REopt GHP LCCA Analysis.", default: 'system_parameter.json', short: :y

          opt :modelica_model, "\Path to GHP Modelica project dir created and run previously. This is a required argument for the REopt GHP LCCA Analysis.", default: 'modelica', short: :m

          opt :scenario, "\nSelect which scenario to optimize", default: 'baseline_scenario.csv', required: true, short: :s

          opt :feature, "\nSelect which FeatureFile to use", default: 'example_project.json', required: true, short: :f
        end
      end

      # Define visualization commands
      def opt_visualize
        @subopts = Optimist.options do
          banner "\nURBANopt visualize:\n \n"

          opt :feature, "\nVisualize results for all scenarios for a feature file\n" \
            "Provide the FeatureFile to visualize each associated scenario\n" \
            "Example: uo visualize --feature example_project.json\n", type: String, short: :f

          opt :scenario, "\nVisualize results for all features in a scenario\n" \
            "Provide the scenario CSV file to visualize each feature in the scenario\n" \
            "Example: uo visualize --scenario baseline_scenario.csv\n", type: String, short: :s
        end
      end

      # Define validation commands
      def opt_validate
        @subopts = Optimist.options do
          banner "\nURBANopt validate:\n \n"

          opt :eui, "\nCompare eui results in feature reports to limits in validation_schema.yaml\n" \
            "Provide path to the validation_schema.yaml file in your project directory\n" \
            'Example: uo validate --eui validation_schema.yaml', type: String

          opt :scenario, "\nProvide the scenario CSV file to validate features from that scenario\n", type: String, required: true, short: :s

          opt :feature, "\nProvide the Feature JSON file to include info about each feature\n", type: String, required: true, short: :f

          opt :units, "\nSI (kWh/m2/yr) or IP (kBtu/ft2/yr)", type: String, default: 'IP'
        end
      end

      def opt_delete
        @subopts = Optimist.options do
          banner "\nURBANopt delete:\n \n"

          opt :scenario, "\nDelete simulation files for this scenario", default: 'baseline_scenario.csv', required: true
        end
      end

      def opt_des_params
        @subopts = Optimist.options do
          banner "\nURBANopt des_params:\n \n"

          opt :sys_param, "\nBuild a system parameters JSON config file for Modelica District Energy System or Ground Heat Exchanger simulation using URBANopt SDK outputs\n" \
            "Provide path/name of json file to be created\n" \
            'Example: uo des_params --sys-param path/to/sys_params.json', type: String, required: true, short: :y

          opt :scenario, "\nPath to the scenario CSV file\n" \
            "Example: uo des_params --sys-param path/to/sys_params.json --scenario path/to/baseline_scenario.csv\n", type: String, required: true, short: :s

          opt :feature, "\nPath to the feature JSON file\n" \
            "Example: uo des_params --sys-param path/to/sys_params.json --feature path/to/example_project.json\n", type: String, required: true, short: :f

          opt :model_type, "\nSelection for which kind of DES simulation to perform\n" \
            "Valid choices: 'time_series']\n" \
            'If not specified, the default time_series simulation type will be used', type: String, short: :m

          opt :district_type, "\nSelection for which kind of district system parameters to generate\n" \
            "Example: uo des_params --sys-param path/to/sys_params.json --feature path/to/example_project.json --district-type 5G_ghe\n" \
            "Available options are: ['4G', '5G_ghe']\n" \
            'If not specified, the default 4G district type will be used', type: String, short: :t

          opt :overwrite, "\nDelete and rebuild existing sys-param file\n", short: :o
          'Example: uo des_params --sys-param path/to/sys_params.json --feature path/to/example_project.json --overwrite'
        end
      end

      def opt_des_create
        @subopts = Optimist.options do
          banner "\nURBANopt des_create:\n"

          opt :sys_param, "\nPath to system parameters config file, possibly created with 'des_params' command in this CLI\n" \
            "Example: uo des_create --sys-param system_parameters.json\n", type: String, required: true, short: :y

          opt :feature, "\nPath to the feature JSON file\n" \
            'Example: uo des_create --feature path/to/example_project.json', type: String, required: true, short: :f

          opt :des_name, "\nPath to Modelica project dir to be created\n" \
            'Example: uo des_create --des-name path/to/example_modelica_project', type: String, short: :n

          opt :overwrite, "\nDelete and rebuild existing model directory\n", short: :o
          'Example: uo des_create --des-name path/to/example_modelica_project --overwrite'
        end
      end

      def opt_des_run
        @subopts = Optimist.options do
          banner "\nURBANopt des_run:\n \n"

          opt :model, "\nPath to Modelica model dir, possibly created with 'des_create' command in this CLI\n" \
            'Example: uo des_run --model path/to/model/dir', type: String, required: true

          opt :start_time, "\nStart time of the simulation (seconds of a year)\n", type: Integer, required: false, short: :a\

          opt :stop_time, "\nStop time of the simulation (seconds of a year)\n", type: Integer, required: false, short: :z\

          opt :step_size, "\nStep size of the simulation (seconds)\n", type: Integer, required: false, short: :x\

          opt :interval, "\nNumber of intervals to divide the simulation into (alternative to step_size)\n", type: Integer, required: false, short: :i\
        end
      end

      def opt_des_process
        @subopts = Optimist.options do
          banner "\nURBANopt #{@command}:\n \n"

          opt :model, "\nPath to Modelica model dir, possibly created with 'des_create' command in this CLI\n" \
            'Example: uo des_process --model path/to/model/dir', type: String, required: true
        end
      end

      def opt_ghe_size
        @subopts = Optimist.options do
          banner "\nURBANopt ghe_size:\n \n"

          opt :sys_param, "Path to system parameters config file, possibly created with 'des_params' command in this CLI\n" \
            "Example: uo ghe_size --sys-param path/to/sys_params.json --scenario path/to/baseline_scenario.csv --feature path/to/example_project.json\n", type: String, required: true, short: :y

          opt :scenario, "\nPath to the scenario CSV file\n" \
            "Example: uo ghe_size --sys-param-file path/to/sys_params.json --scenario path/to/baseline_scenario.csv --feature path/to/example_project.json\n", type: String, required: true, short: :s

          opt :feature, "\nPath to the feature JSON file\n" \
            "Example: uo ghe_size --sys-param-file path/to/sys_params.json --feature path/to/example_project.json\n", type: String, required: true, short: :f
        end
      end
      attr_reader :mainopts, :command, :subopts
    end

    # Initialize the CLI class
    @opthash = UrbanOptCLI.new

    # Rescue if user only enters 'uo' without a command
    begin
      # Pull out feature and scenario filenames and paths
      if @opthash.subopts[:scenario_file]
        @feature_path, @feature_name = File.split(File.expand_path(@opthash.subopts[:scenario_file]))
      end
    rescue NoMethodError
      abort('Invalid command, please run uo --help for a list of available commands')
    rescue StandardError => e
      puts "\nERROR: #{e.message}"
    end

    # FIXME: Can this be combined with the above block? This isn't very DRY
    # One solution would be changing scenario_file to feature.
    #   Would that be confusing when creating a ScenarioFile from the FeatureFile?
    if @opthash.subopts[:feature]
      @feature_path, @feature_name = Pathname(File.expand_path(@opthash.subopts[:feature])).split
    end
    if @opthash.subopts[:scenario]
      @root_dir, @scenario_file_name = Pathname(File.expand_path(@opthash.subopts[:scenario])).split
      @scenario_name = File.basename(@scenario_file_name, File.extname(@scenario_file_name))
    end

    # Simulate energy usage as defined by ScenarioCSV
    def self.run_func
      run_dir = @root_dir / 'run' / @scenario_name.downcase
      csv_file = @root_dir / @scenario_file_name
      featurefile = @root_dir / @feature_name
      mapper_files_dir = @root_dir / 'mappers'
      reopt_files_dir = @root_dir / 'reopt/'
      num_header_rows = 1

      if @feature_id
        feature_run_dir = run_dir / @feature_id
        # If run folder for feature exists, remove it
        FileUtils.rm_rf(feature_run_dir) if feature_run_dir.exist?
      end

      feature_file = URBANopt::GeoJSON::GeoFile.from_file(featurefile)
      if @opthash.subopts[:reopt] == true || @opthash.subopts[:reopt_scenario] == true || @opthash.subopts[:reopt_feature] == true
        parsed_scenario_file = CSV.read(csv_file, headers: true, col_sep: ',')
        # TODO: determine what to do if multiple assumptions are provided
        # num_unique_reopt_assumptions = parsed_scenario_file['REopt Assumptions'].tally.size
        # Use the first assumption as the default
        reopt_assumptions_filename = parsed_scenario_file['REopt Assumptions'][0]
        scenario_output = URBANopt::Scenario::REoptScenarioCSV.new(
          @scenario_name.downcase,
          @root_dir,
          run_dir,
          feature_file,
          mapper_files_dir,
          csv_file,
          num_header_rows,
          reopt_files_dir,
          reopt_assumptions_filename
        )
      else
        scenario_output = URBANopt::Scenario::ScenarioCSV.new(
          @scenario_name.downcase,
          @root_dir,
          run_dir,
          feature_file,
          mapper_files_dir,
          csv_file,
          num_header_rows
        )
      end
      scenario_output
    end

    # Create a scenario csv file from a FeatureFile
    # params\
    # +feature_file_path+:: _string_ Optional - ID of a single feature in a feature file.
    def self.create_scenario_csv_file(feature_id)
      begin
        feature_file_json = JSON.parse(File.read(File.expand_path(@opthash.subopts[:scenario_file])), symbolize_names: true)
      # Rescue if user provides path to a dir and not a file
      rescue Errno::EISDIR => e
        wrong_path = e.to_s.split(' - ')[-1]
        abort("\nOops! '#{wrong_path}' is a directory. Please provide path to the geojson feature_file")
        # Rescue if file isn't json
      rescue JSON::ParserError => e
        abort("\nOops! You didn't provide a json file. Please provide path to the geojson feature_file")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end
      Dir["#{@feature_path}/mappers/*.rb"].each do |mapper_file|
        mapper_name = File.basename(mapper_file, File.extname(mapper_file))
        scenario_file_name = if feature_id == 'SKIP'
                               "#{mapper_name.downcase}_scenario.csv"
                             else
                               "#{mapper_name.downcase}_scenario-#{feature_id}.csv"
                             end
        CSV.open(File.join(@feature_path, scenario_file_name), 'wb', write_headers: true,
                                                                     headers: ['Feature Id', 'Feature Name', 'Mapper Class']) do |csv|
          feature_file_json[:features].each do |feature|
            if feature_id == 'SKIP'
              # ensure that feature is a building
              if feature[:properties][:type] == 'Building'
                csv << [feature[:properties][:id], feature[:properties][:name], "URBANopt::Scenario::#{mapper_name}Mapper"]
              end
            elsif feature_id == feature[:properties][:id]
              csv << [feature[:properties][:id], feature[:properties][:name], "URBANopt::Scenario::#{mapper_name}Mapper"]
            elsif unless feature_file_json[:features].any? { |hash| hash[:properties][:id].include?(feature_id.to_s) }
                    abort("\nYou must provide Feature ID from FeatureFile!\n---\n\n")
                  end
              # If Feature ID specified does not exist in the Feature File raise error
            end
          end
          # Rescue if json isn't a geojson feature_file
        rescue NoMethodError
          abort("\nOops! You didn't provide a valid feature_file. Please provide path to the geojson feature_file")
        rescue StandardError => e
          puts "\nERROR: #{e.message}"
        end
      end
    end

    # Write new ScenarioFile with REopt column
    # params \
    # +existing_scenario_file+:: _string_ - Name of existing ScenarioFile
    def self.create_reopt_scenario_file(existing_scenario_file)
      existing_path, existing_name = File.split(File.expand_path(existing_scenario_file))
      # make reopt folder (if it does not exist)
      unless Dir.exist?(File.join(existing_path, 'reopt'))
        Dir.mkdir File.join(existing_path, 'reopt')
        # copy reopt files from cli examples
        $LOAD_PATH.each do |path_item|
          if path_item.to_s.end_with?('example_files')
            reopt_files = File.join(path_item, 'reopt')
            Pathname.new(reopt_files).children.each { |reopt_file| FileUtils.cp(reopt_file, File.join(existing_path, 'reopt')) }
          end
        end
      end

      table = CSV.read(existing_scenario_file, headers: true, col_sep: ',')
      # Add another column, row by row:
      table.each do |row|
        row['REopt Assumptions'] = 'multiPV_assumptions.json'
      end
      # write new file (name it REopt + existing scenario name)
      CSV.open(File.join(existing_path, "REopt_#{existing_name}"), 'w') do |f|
        f << table.headers
        table.each { |row| f << row }
      end
    end

    # Change num_parallel in runner.conf to set number of cores to use when running simulations
    # This function is called during project_dir creation/updating so users aren't surprised if they look at the config file
    def self.use_num_parallel(project_dir)
      if ENV['UO_NUM_PARALLEL'] || @opthash.subopts[:num_parallel]
        runner_file_path = Pathname(project_dir) / 'runner.conf'
        runner_conf_hash = JSON.parse(File.read(runner_file_path))
        if @opthash.subopts[:num_parallel]
          runner_conf_hash['num_parallel'] = @opthash.subopts[:num_parallel]
          File.open(runner_file_path, 'w+') do |f|
            f << runner_conf_hash.to_json
          end
        elsif ENV['UO_NUM_PARALLEL']
          runner_conf_hash['num_parallel'] = ENV['UO_NUM_PARALLEL'].to_i
          File.open(runner_file_path, 'w+') do |f|
            f << runner_conf_hash.to_json
          end
        end
      end
    end

    # Create project folder
    # params\
    # +dir_name+:: _string_ Name of new project folder
    #
    # Includes weather for example location, a base workflow file, and mapper files to show a baseline and a high-efficiency option.
    def self.create_project_folder(dir_name, empty_folder: false, overwrite_project: false)
      project_path = Pathname(dir_name)
      case overwrite_project
      when true
        if Dir.exist?(project_path)
          FileUtils.rm_rf(project_path)
        end
      when false
        if Dir.exist?(project_path)
          abort("\nERROR:  there is already a directory at #{project_path}... aborting\n---\n\n")
        end
      end

      $LOAD_PATH.each do |path_item|
        if path_item.to_s.end_with?('example_files')
          example_files_dir = Pathname(path_item)

          case empty_folder
          when false

            project_path.mkdir
            project_path.join('weather').mkdir
            project_path.join('mappers').mkdir
            project_path.join('osm_building').mkdir
            project_path.join('visualization').mkdir
            if @opthash.subopts[:electric] == true || @opthash.subopts[:disco] == true
              # make opendss folder
              project_path.join('opendss').mkdir
              if @opthash.subopts[:disco] == true
                # make disco folder
                project_path.join('disco').mkdir
              end
            end

            # copy config file
            FileUtils.cp(example_files_dir / 'runner.conf', project_path)
            use_num_parallel(project_path)

            # copy gemfile
            FileUtils.cp(example_files_dir / 'Gemfile', project_path)

            # copy validation schema
            FileUtils.cp(example_files_dir / 'validation_schema.yaml', project_path)

            # copy weather files
            weather_files = example_files_dir / 'weather'
            weather_files.children.each { |weather_file| FileUtils.cp(weather_file, project_path / 'weather') }

            # copy visualization files
            viz_files = example_files_dir / 'visualization'
            viz_files.children.each { |viz_file| FileUtils.cp(viz_file, project_path / 'visualization') }

            if @opthash.subopts[:electric] == true || @opthash.subopts[:disco] == true
              # also copy opendss files
              dss_files = example_files_dir / 'opendss'
              dss_files.children.each { |file| FileUtils.cp(file, project_path / 'opendss') }
              if @opthash.subopts[:electric] == true
                FileUtils.cp(example_files_dir / 'example_project_with_electric_network.json', project_path)
              elsif @opthash.subopts[:disco] == true
                # TODO: update this once there is a FeatureFile for Disco
                FileUtils.cp(example_files_dir / 'example_project_with_electric_network.json', project_path)
                disco_files = example_files_dir / 'disco'
                disco_files.children.each { |file| FileUtils.cp(file, project_path / 'disco') }
              end
            elsif @opthash.subopts[:ghe] == true
              FileUtils.cp(example_files_dir / 'example_project_with_ghe.json', project_path)
            elsif @opthash.subopts[:streets] == true
              FileUtils.cp(example_files_dir / 'example_project_with_streets.json', project_path)
            elsif @opthash.subopts[:photovoltaic] == true
              FileUtils.cp(example_files_dir / 'example_project_with_PV.json', project_path)
            end

            case @opthash.subopts[:floorspace]
            when false

              if @opthash.subopts[:electric] != true && @opthash.subopts[:streets] != true && @opthash.subopts[:photovoltaic] != true && @opthash.subopts[:disco] != true && @opthash.subopts[:ghe] != true
                # copy feature file
                FileUtils.cp(example_files_dir / 'example_project.json', project_path)
              end

              # copy osm
              FileUtils.cp(example_files_dir / 'osm_building' / '7.osm', project_path / 'osm_building')
              FileUtils.cp(example_files_dir / 'osm_building' / '8.osm', project_path / 'osm_building')
              FileUtils.cp(example_files_dir / 'osm_building' / '9.osm', project_path / 'osm_building')

              case @opthash.subopts[:create_bar]
              when false

                # copy the mappers
                FileUtils.cp(example_files_dir / 'mappers' / 'Baseline.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'HighEfficiency.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'ThermalStorage.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'EvCharging.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'FlexibleHotWater.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'ChilledWaterStorage.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'PeakHoursThermostatAdjust.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'PeakHoursMelsShedding.rb', project_path / 'mappers')

                # copy osw file
                FileUtils.cp(example_files_dir / 'mappers' / 'base_workflow.osw', project_path / 'mappers')

              when true

                # copy the mappers
                FileUtils.cp(example_files_dir / 'mappers' / 'CreateBar.rb', project_path / 'mappers')
                FileUtils.cp(example_files_dir / 'mappers' / 'HighEfficiencyCreateBar.rb', project_path / 'mappers')

                # copy osw file
                FileUtils.cp(example_files_dir / 'mappers' / 'createbar_workflow.osw', project_path / 'mappers')

              end

            when true

              # copy the mappers
              FileUtils.cp(example_files_dir / 'mappers' / 'Floorspace.rb', project_path / 'mappers')
              FileUtils.cp(example_files_dir / 'mappers' / 'HighEfficiencyFloorspace.rb', project_path / 'mappers')

              # copy osw file
              FileUtils.cp(example_files_dir / 'mappers' / 'floorspace_workflow.osw', project_path / 'mappers')

              # copy feature file
              FileUtils.cp(example_files_dir / 'example_floorspace_project.json', project_path)

              # copy osm
              FileUtils.cp(example_files_dir / 'osm_building' / '7_floorspace.json', project_path / 'osm_building')
              FileUtils.cp(example_files_dir / 'osm_building' / '7_floorspace.osm', project_path / 'osm_building')
              FileUtils.cp(example_files_dir / 'osm_building' / '8.osm', project_path / 'osm_building')
              FileUtils.cp(example_files_dir / 'osm_building' / '9.osm', project_path / 'osm_building')
            end

            if @opthash.subopts[:class_coincident]
              # copy residential files
              FileUtils.cp_r(example_files_dir / 'mappers' / 'residential', project_path / 'mappers' / 'residential')
              FileUtils.cp_r(example_files_dir / 'measures', project_path / 'measures')
              FileUtils.cp_r(example_files_dir / 'resources', project_path / 'resources')
              FileUtils.cp_r(example_files_dir / 'xml_building', project_path / 'xml_building')
              # copy class project files
              FileUtils.cp(example_files_dir / 'class_project_coincident.json', dir_name)
              FileUtils.cp(example_files_dir / 'mappers' / 'class_project_workflow.osw', project_path / 'mappers' / 'base_workflow.osw')
              FileUtils.cp(example_files_dir / 'mappers' / 'ClassProject.rb', project_path / 'mappers')

              if File.exist?(project_path / 'example_project.json')
                FileUtils.remove(project_path / 'example_project.json')
              end

            end

            if @opthash.subopts[:class_diverse]
              # copy residential files
              FileUtils.cp_r(example_files_dir / 'mappers' / 'residential', project_path / 'mappers' / 'residential')
              FileUtils.cp_r(example_files_dir / 'measures', project_path / 'measures')
              FileUtils.cp_r(example_files_dir / 'resources', project_path / 'resources')
              FileUtils.cp_r(example_files_dir / 'xml_building', project_path / 'xml_building')
              # copy class project files
              FileUtils.cp(example_files_dir / 'class_project_diverse.json', dir_name)
              FileUtils.cp(example_files_dir / 'mappers' / 'class_project_workflow.osw', project_path / 'mappers' / 'base_workflow.osw')
              FileUtils.cp(example_files_dir / 'mappers' / 'ClassProject.rb', project_path / 'mappers')

              if File.exist?(project_path / 'example_project.json')
                FileUtils.remove(project_path / 'example_project.json')
              end

            end

            if @opthash.subopts[:combined]
              # copy residential files
              FileUtils.cp_r(example_files_dir / 'mappers' / 'residential', project_path / 'mappers' / 'residential')
              FileUtils.cp_r(example_files_dir / 'measures', project_path / 'measures')
              FileUtils.cp_r(example_files_dir / 'resources', project_path / 'resources')
              FileUtils.cp(example_files_dir / 'example_project_combined.json', dir_name)
              FileUtils.cp_r(example_files_dir / 'xml_building', project_path / 'xml_building')
              if File.exist?(project_path / 'example_project.json')
                FileUtils.remove(project_path / 'example_project.json')
              end
            end

          when true
            project_path.mkdir
            FileUtils.cp(example_files_dir / 'Gemfile', project_path / 'Gemfile')
            FileUtils.cp_r(example_files_dir / 'mappers', project_path / 'mappers')
            FileUtils.cp_r(example_files_dir / 'visualization', project_path / 'visualization')

            if @opthash.subopts[:combined]
              # copy residential files
              FileUtils.cp_r(example_files_dir / 'mappers' / 'residential', project_path / 'mappers' / 'residential')
              FileUtils.cp_r(example_files_dir / 'measures', project_path / 'measures')
              FileUtils.cp_r(example_files_dir / 'resources', project_path / 'resources')
              FileUtils.cp(example_files_dir / 'example_project_combined.json', dir_name)
              if File.exist?(project_path / 'example_project.json')
                FileUtils.remove(project_path / 'example_project.json')
              end
            end
          end
        end
      end
    end

    # Update an existing URBANopt Project
    # params\
    # +existing_project_folder+:: _string_ Name of existing project folder
    # +new_project_directory+:: _string_ Location of updated URBANopt project
    #
    # Includes weather for example location, a base workflow file, and mapper files to show a baseline and a high-efficiency option.
    def self.update_project(existing_project_folder, new_project_directory)
      original_path = Pathname.new(existing_project_folder).expand_path
      new_path = Pathname.new(new_project_directory)

      if Dir.exist?(new_path)
        abort("\nERROR:  there is already a directory here named #{new_path}... aborting\n---\n\n")
      end

      FileUtils.copy_entry(original_path, new_path)

      $LOAD_PATH.each do |path_item|
        if path_item.to_s.end_with?('example_files')
          example_files_dir = Pathname(path_item)

          # copy gemfile
          FileUtils.cp_r(example_files_dir / 'Gemfile', new_path, remove_destination: true)

          # copy validation schema
          FileUtils.cp_r(example_files_dir / 'validation_schema.yaml', new_path, remove_destination: true)

          # copy config file
          FileUtils.cp_r(example_files_dir / 'runner.conf', new_path, remove_destination: true)
          use_num_parallel(new_path)

          # Replace standard mappers
          # FIXME: this also copies createBar and Floorspace without checking project type (for now)
          mappers = example_files_dir / 'mappers'
          mappers.children.each { |mapper| FileUtils.cp_r(mapper, new_path / 'mappers', remove_destination: true) }

          # Replace OSM files
          if (original_path / 'osm_building').directory?
            (example_files_dir / 'osm_building').children.each { |res| FileUtils.cp_r(res, new_path / 'osm_building', remove_destination: true) }
          end

          # Replace weather
          if (original_path / 'weather').directory?
            (example_files_dir / 'weather').children.each { |weather_file| FileUtils.cp_r(weather_file, new_path / 'weather', remove_destination: true) }
          end

          # Replace visualization files
          (example_files_dir / 'visualization').children.each { |viz| FileUtils.cp_r(viz, new_path / 'visualization', remove_destination: true) }

          # Replace Residential files
          if (original_path / 'residential').directory?
            (example_files_dir / 'residential').children.each { |res| FileUtils.cp_r(res, new_path / 'mappers' / 'residential', remove_destination: true) }
          end
          if (original_path / 'measures').directory?
            (example_files_dir / 'measures').children.each { |res| FileUtils.cp_r(res, new_path / 'measures', remove_destination: true) }
          end
          if (original_path / 'resources').directory?
            (example_files_dir / 'resources').children.each { |res| FileUtils.cp_r(res, new_path / 'resources', remove_destination: true) }
            # hpxml-measures is included in resources/residential-measures/resources/ and is redundant if present in an existing project when updating
            if (original_path / 'resources' / 'hpxml-measures').directory?
              FileUtils.rm_rf(new_path / 'resources' / 'hpxml-measures')
            end
          end
          # adjust for residential workflow
          if (original_path / 'xml_building').directory?
            (example_files_dir / 'xml_building').children.each { |res| FileUtils.cp_r(res, new_path / 'xml_building', remove_destination: true) }
          end

          # Replace Reopt assumption files
          if (original_path / 'reopt').directory?
            (example_files_dir / 'reopt').children.each { |reopt_file| FileUtils.cp_r(reopt_file, new_path / 'reopt', remove_destination: true) }
          end

          # Replace OpenDSS files
          if (original_path / 'opendss').directory?
            (example_files_dir / 'opendss').children.each { |opendss_file| FileUtils.cp_r(opendss_file, new_path / 'opendss', remove_destination: true) }
          end

          if (original_path / 'disco').directory?
            (example_files_dir / 'disco').children.each { |disco_file| FileUtils.cp_r(disco_file, new_path / 'disco', remove_destination: true) }
          end

          original_path.children.each do |file|
            if File.extname(file) == '.json'
              puts file
              if File.exist?(example_files_dir / file)
                FileUtils.cp_r(example_files_dir / file, new_path)
              end
            end
          end

        end
      end
    end

    # Setup Python Variables for DiTTo and DISCO
    def self.setup_python_variables
      pvars = {
        python_version: '3.10',
        miniconda_version: '24.9.2-0',
        python_install_path: nil,
        python_path: nil,
        pip_path: nil,
        ditto_path: nil,
        gmt_path: nil,
        ghe_path: nil
      }

      # get location
      $LOAD_PATH.each do |path_item|
        if path_item.to_s.end_with?('example_files')
          # install python in cli gem's example_files/python_deps folder
          # so it is accessible to all projects
          pvars[:python_install_path] = File.join(path_item, 'python_deps')
          pvars[:pip_path] = pvars[:python_install_path]
          break
        end
      end
      # look for config file and grab info
      if File.exist? File.join(pvars[:python_install_path], 'python_config.json')
        configs = JSON.parse(File.read(File.join(pvars[:python_install_path], 'python_config.json')), symbolize_names: true)
        pvars[:python_path] = configs[:python_path]
        pvars[:pip_path] = configs[:pip_path]
        pvars[:ditto_path] = configs[:ditto_path]
        pvars[:gmt_path] = configs[:gmt_path]
        pvars[:disco_path] = configs[:disco_path]
        pvars[:ghe_path] = configs[:ghe_path]
      end
      return pvars
    end

    # Return UO python packages list from python_deps/dependencies.json
    def self.get_python_deps
      deps = []
      the_path = ''
      $LOAD_PATH.each do |path_item|
        if path_item.to_s.end_with?('example_files')
          # install python in cli gem's example_files/python_deps folder
          # so it is accessible to all projects
          the_path = File.join(path_item, 'python_deps')
          break
        end
      end

      if File.exist? File.join(the_path, 'dependencies.json')
        deps = JSON.parse(File.read(File.join(the_path, 'dependencies.json')), symbolize_names: true)
      end
      return deps
    end

    # Check Python
    def self.check_python(python_only: false)
      results = { python: false, pvars: [], message: [], python_deps: false, result: false }
      puts 'Checking system.....'
      pvars = setup_python_variables
      results[:pvars] = pvars

      # check vars
      if pvars[:python_path].nil? || pvars[:pip_path].nil?
        # need to install
        results[:message] << 'Python paths have not yet been initialized with URBANopt.'
        puts results[:message]
        return results
      end

      # check python
      stdout, stderr, status = Open3.capture3("#{pvars[:python_path]} -V")
      if stderr.empty?
        puts "...python found at #{pvars[:python_path]}"
      else
        results[:message] << "ERROR installing python: #{stderr}"
        puts results[:message]
        return results
      end

      # check pip
      stdout, stderr, status = Open3.capture3("#{pvars[:pip_path]} -V")
      if stderr.empty?
        puts "...pip found at #{pvars[:pip_path]}"
      else
        results[:message] << "ERROR finding pip: #{stderr}"
        puts results[:message]
        return results
      end

      # python and pip installed correctly
      results[:python] = true

      # now check dependencies (if python_only is false)
      unless python_only
        deps = get_python_deps
        puts "DEPENDENCIES RETRIEVED FROM FILE: #{deps}"
        errors = []
        deps.each do |dep|
          # TODO: Update when there is a stable release for DISCO
          if dep[:name].to_s.include? 'disco'
            stdout, stderr, status = Open3.capture3("#{pvars[:pip_path]} show NREL-disco")
          else
            stdout, stderr, status = Open3.capture3("#{pvars[:pip_path]} show #{dep[:name]}")
          end
          if @opthash.subopts[:verbose]
            puts dep[:name]
            puts "stdout: #{stdout}"
            puts "status: #{status}"
          end

          if stderr.empty?
            # check versions
            m = stdout.match(/^Version: (\S{3,}$)/)
            err = true
            if m && m.size > 1
              if !dep[:version].nil? && dep[:version].to_s == m[1].to_s
                puts "...#{dep[:name]} found with specified version #{dep[:version]}"
                err = false
              elsif dep[:version].nil?
                err = false
                puts "...#{dep[:name]} found (version #{m[1]})"
              end
            end
            if err
              results[:message] << "incorrect version found for #{dep[:name]}...expecting version #{dep[:version]}"
              puts results[:message]
              errors << stderr
            end
          else
            # ignore warnings
            unless stderr.include? 'WARNING:'
              results[:message] << stderr
              puts results[:message]
              errors << stderr
            end
          end
        end
        if errors.empty?
          results[:python_deps] = true
        end
      end

      # all is good if messages are empty
      if results[:message].empty?
        results[:result] = true
      end

      return results
    end

    # Install Python and Related Dependencies
    def self.install_python_dependencies
      pvars = setup_python_variables

      # check if python and dependencies are already installed
      results = check_python

      # install python if not installed
      if !results[:python]

        # cd into script dir
        wd = Dir.getwd
        FileUtils.cd(pvars[:python_install_path])
        puts "Installing Python #{pvars[:python_version]}..."
        if (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM).nil?
          # not windows
          script = File.join(pvars[:python_install_path], 'install_python.sh')
          the_command = "cd #{pvars[:python_install_path]}; #{script} #{pvars[:miniconda_version]} #{pvars[:python_version]} #{pvars[:python_install_path]}"
          stdout, stderr, status = Open3.capture3(the_command)
          if (stderr && !stderr == '') || (stdout && stdout.include?('Usage'))
            # error
            puts "ERROR installing python dependencies: #{stderr}, #{stdout}"
            return
          end
          # capture paths
          mac_path_base = File.join(pvars[:python_install_path], "Miniconda-#{pvars[:miniconda_version]}")
          pvars[:python_path] = File.join(mac_path_base, 'bin', 'python')
          pvars[:pip_path] = File.join(mac_path_base, 'bin', 'pip')
          pvars[:ditto_path] = File.join(mac_path_base, 'bin', 'ditto_reader_cli')
          pvars[:gmt_path] = File.join(mac_path_base, 'bin', 'uo_des')
          pvars[:disco_path] = File.join(mac_path_base, 'bin', 'disco')
          pvars[:ghe_path] = File.join(mac_path_base, 'bin', 'thermalnetwork')
          configs = {
            python_path: pvars[:python_path],
            pip_path: pvars[:pip_path],
            ditto_path: pvars[:ditto_path],
            gmt_path: pvars[:gmt_path],
            disco_path: pvars[:disco_path],
            ghe_path: pvars[:ghe_path]
          }
        else
          # windows
          script = File.join(pvars[:python_install_path], 'install_python.ps1')

          command_list = [
            'powershell Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process',
            "powershell #{script} #{pvars[:miniconda_version]} #{pvars[:python_version]} #{pvars[:python_install_path]}",
            'powershell $env:CONDA_DLL_SEARCH_MODIFICATION_ENABLE = 1'
          ]

          command_list.each do |command|
            stdout, stderr, status = Open3.capture3(command)
            if !stderr.empty?
              puts "ERROR installing python dependencies: #{stderr}, #{stdout}"
              break
            end
          end

          # capture paths
          windows_path_base = File.join(pvars[:python_install_path], "python-#{pvars[:python_version]}")
          pvars[:python_path] = File.join(windows_path_base, 'python.exe')
          pvars[:pip_path] = File.join(windows_path_base, 'Scripts', 'pip.exe')
          pvars[:ditto_path] = File.join(windows_path_base, 'Scripts', 'ditto_reader_cli.exe')
          pvars[:gmt_path] = File.join(windows_path_base, 'Scripts', 'uo_des.exe')
          pvars[:disco_path] = File.join(windows_path_base, 'Scripts', 'disco.exe')
          pvars[:ghe_path] = File.join(windows_path_base, 'Scripts', 'thermalnetwork.exe')

          configs = {
            python_path: pvars[:python_path],
            pip_path: pvars[:pip_path],
            ditto_path: pvars[:ditto_path],
            gmt_path: pvars[:gmt_path],
            disco_path: pvars[:disco_path],
            ghe_path: pvars[:ghe_path]
          }
        end

        # get back to wd
        FileUtils.cd(wd)

        # write config file
        File.open(File.join(pvars[:python_install_path], 'python_config.json'), 'w') do |f|
          f.write(JSON.pretty_generate(configs))
        end
      end

      # install python dependencies if not installed
      if !results[:python_deps]
        deps = get_python_deps
        deps.each do |dep|
          puts "Installing #{dep[:name]} #{dep[:version]}"
          the_command = ''
          if dep[:version].nil?
            the_command = "#{pvars[:pip_path]} install #{dep[:name]}"
          else
            the_command = "#{pvars[:pip_path]} install #{dep[:name]}==#{dep[:version]}"
          end

          if @opthash.subopts[:verbose]
            puts "INSTALL COMMAND: #{the_command}"
          end
          stdout, stderr, status = Open3.capture3(the_command)
          if @opthash.subopts[:verbose]
            puts "status: #{status}"
            puts "stdout: #{stdout}"
          end
          if !stderr.empty?
            puts "Error installing: #{stderr}"
          end
        end
      end

      # double check python and dependencies have been installed now
      if !results[:result]
        # double check that everything has succeeded now
        results = check_python
      end

      if results[:result]
        puts "Python and dependencies successfully installed in #{pvars[:python_install_path]}"
      else
        # errors occurred
        puts "Errors occurred when installing python and dependencies: #{results[:message]}"
      end
    end

    # Perform CLI actions

    # Create new project folder
    if @opthash.command == 'create' && @opthash.subopts[:project_folder] && @opthash.subopts[:empty] == false
      case @opthash.subopts[:overwrite]
      when true
        puts "\nOverwriting existing project folder: #{@opthash.subopts[:project_folder]}...\n\n"
        create_project_folder(@opthash.subopts[:project_folder], empty_folder: false, overwrite_project: true)
      when false
        puts "\nCreating a new project folder...\n"
        create_project_folder(@opthash.subopts[:project_folder], empty_folder: false, overwrite_project: false)
        if @opthash.subopts[:floorspace] == false && @opthash.subopts[:create_bar] == true
          puts "\nAn example FeatureFile is included: 'example_project.json'. You may place your own FeatureFile alongside the example."
        elsif @opthash.subopts[:floorspace] == true && @opthash.subopts[:create_bar] == false
          puts "\nAn example FeatureFile is included: 'example_floorspace_project.json'. You may place your own FeatureFile alongside the example."
        end
        puts 'Weather data is provided for the example FeatureFile. Additional weather data files may be downloaded from energyplus.net/weather for free'
        puts "If you use additional weather files, ensure they are added to the 'weather' directory. You will need to configure your mapper file and your osw file to use the desired weather file"
        puts "We recommend using absolute paths for all commands, for cleaner output\n"
      end
    elsif @opthash.command == 'create' && @opthash.subopts[:project_folder] && @opthash.subopts[:empty] == true
      case @opthash.subopts[:overwrite]
      when true
        puts "\nOverwriting existing project folder: #{@opthash.subopts[:project_folder]} with an empty folder...\n\n"
        create_project_folder(@opthash.subopts[:project_folder], empty_folder: true, overwrite_project: true)
      when false
        puts "\nCreating a new empty project folder...\n"
        create_project_folder(@opthash.subopts[:project_folder], empty_folder: true, overwrite_project: false)
      end
      puts "\nAdd your FeatureFile in the Project directory you just created."
      puts 'Add your weather data files in the Weather folder. They may be downloaded from energyplus.net/weather for free'
      puts 'Add your OpenStudio models for Features in your Feature file, if any in the osm_building folder'
      puts "We recommend using absolute paths for all commands, for cleaner output\n"
    end

    # Create ScenarioFile from FeatureFile
    if @opthash.command == 'create' && @opthash.subopts[:scenario_file]
      if @opthash.subopts[:single_feature]
        puts "\nBuilding sample ScenarioFiles, assigning mapper classes to Feature ID #{@opthash.subopts[:single_feature]}"
        create_scenario_csv_file(@opthash.subopts[:single_feature])
        puts "\nDone\n"
      else
        puts "\nBuilding sample ScenarioFiles, assigning mapper classes to each feature from #{@feature_name}"
        # Skip Feature ID argument if not present
        create_scenario_csv_file('SKIP')
        puts "\nDone\n"
      end
    end

    # Create REopt ScenarioFile from existing
    if @opthash.command == 'create' && @opthash.subopts[:reopt_scenario_file]
      puts "\nCreating ScenarioFile with REopt functionality, extending from #{@opthash.subopts[:reopt_scenario_file]}..."
      create_reopt_scenario_file(@opthash.subopts[:reopt_scenario_file])
      puts "\nDone"
    end

    # Graceful error if no flag is provided when using `create` command
    if @opthash.command == 'create' &&
       @opthash.subopts[:scenario_file].nil? &&
       @opthash.subopts[:reopt_scenario_file].nil? &&
       @opthash.subopts[:project_folder].nil?
      abort("\nNo options provided for the `create` command. Did you forget a flag? Perhaps `-p`? See `uo create --help` for all options\n")
    end

    # Update existing URBANopt Project files
    if @opthash.command == 'update'
      puts "\nUpdating files in URBANopt project #{@opthash.subopts[:existing_project_folder]} and storing them in updated project folder at #{@opthash.subopts[:new_project_directory]}..."
      update_project(@opthash.subopts[:existing_project_folder].to_s, @opthash.subopts[:new_project_directory].to_s)
      puts "\nProject files updated to URBANopt CLI Version #{URBANopt::CLI::VERSION}...double check your runner.conf file as well as any other files you may have previously manually configured."
      puts "\nDone"
    end

    # Install python and other dependencies
    if @opthash.command == 'install_python'
      puts "\nInstalling python and dependencies"
      install_python_dependencies
      puts "\nDone\n"
    end

    # Run simulations
    if @opthash.command == 'run' && @opthash.subopts[:scenario] && @opthash.subopts[:feature]
      use_num_parallel(@root_dir)

      if @opthash.subopts[:scenario].to_s.include? '-'
        @feature_id = (@feature_name.to_s.split(/\W+/)[1])
      end

      puts "\nSimulating features of '#{@feature_name}' as directed by '#{@scenario_file_name}'...\n\n"
      scenario_runner = URBANopt::Scenario::ScenarioRunnerOSW.new
      scenario_runner.run(run_func)
      puts "\nDone\n"
    end

    # Run OpenDSS simulation
    if @opthash.command == 'opendss'

      # first check python
      res = check_python
      if res[:python] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      end

      # If a config file is supplied, use the data specified there.
      if @opthash.subopts[:config]

        opendss_config = JSON.parse(File.read(File.expand_path(@opthash.subopts[:config])), symbolize_names: true)
        config_scenario_file = opendss_config[:urbanopt_scenario_file]
        config_scenario_name = File.basename(config_scenario_file, File.extname(config_scenario_file))

        scenario_path = Pathname.new(opendss_config[:urbanopt_scenario_file])
        puts "scenario_path from file: #{scenario_path}"
        # abs vs relative check
        config_path = Pathname.new(File.dirname(File.expand_path(@opthash.subopts[:config])))
        puts "config path from file: #{config_path}"

        puts "Scenario path: #{scenario_path}"

        config_root_dir = config_path
        run_dir = File.join(config_root_dir, 'run', config_scenario_name.downcase)
        featurefile = Pathname.new(opendss_config[:urbanopt_geojson_file])
        if featurefile.relative?
          featurefile = config_path + featurefile
        end

        puts "Run Dir: #{run_dir}"

      elsif @opthash.subopts[:scenario] && @opthash.subopts[:feature]
        # Otherwise use the user-supplied scenario & feature files
        run_dir = File.join(@root_dir, 'run', @scenario_name.downcase)
        featurefile = File.join(@root_dir, @feature_name)
      end

      # Ensure building simulations have been run already
      # check through all since some folder are not datapoints
      begin
        feature_list = Pathname.new(File.expand_path(run_dir)).children.select(&:directory?)
        found_sims = false
        feature_list.each do |fl|
          if File.exist?(File.expand_path(File.join(run_dir, File.basename(fl), 'eplusout.sql')))
            found_sims = true
            break
          end
        end
        if !found_sims
          abort("ERROR: No results found in #{run_dir}. URBANopt simulations are required before using opendss. Please run and process simulations, then try again.\n")
        end
      rescue Errno::ENOENT # Same abort message if there is no run_dir
        abort("ERROR: URBANopt simulations are required before using opendss. Please run and process simulations, then try again.\n")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end

      ditto_cli_root = "#{res[:pvars][:ditto_path]} run-opendss "
      if @opthash.subopts[:config]
        ditto_cli_addition = "--config #{@opthash.subopts[:config]}"
      elsif @opthash.subopts[:scenario] && @opthash.subopts[:feature]
        ditto_cli_addition = "--scenario_file #{@opthash.subopts[:scenario]} --feature_file #{@opthash.subopts[:feature]}"
        if @opthash.subopts[:equipment]
          ditto_cli_addition += " --equipment #{@opthash.subopts[:equipment]}"
        end
        if @opthash.subopts[:timestep]
          ditto_cli_addition += " --timestep #{@opthash.subopts[:timestep]}"
        end
        if @opthash.subopts[:start_date]
          ditto_cli_addition += " --start_date #{@opthash.subopts[:start_date]}"
        end
        if @opthash.subopts[:start_time]
          ditto_cli_addition += " --start_time #{@opthash.subopts[:start_time]}"
        end
        if @opthash.subopts[:end_date]
          ditto_cli_addition += " --end_date #{@opthash.subopts[:end_date]}"
        end
        if @opthash.subopts[:end_time]
          ditto_cli_addition += " --end_time #{@opthash.subopts[:end_time]}"
        end
        if @opthash.subopts[:reopt]
          ditto_cli_addition += ' --reopt'
        end
        if @opthash.subopts[:rnm]
          ditto_cli_addition += ' --rnm'
        end
        if @opthash.subopts[:upgrade]
          ditto_cli_addition += ' --upgrade'
        end
      else
        abort("\nCommand must include ScenarioFile & FeatureFile, or a config file that specifies both. Please try again")
      end
      begin
        puts "COMMAND: #{ditto_cli_root + ditto_cli_addition}"
        system(ditto_cli_root + ditto_cli_addition)
      rescue FileNotFoundError
        abort("\nMust post-process results before running OpenDSS. We recommend 'process --default'." \
        "Once OpenDSS is run, you may then 'process --opendss'")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end
    end

    # Run DISCO Simulation
    if @opthash.command == 'disco'

      # first check python and python dependencies
      res = check_python
      if res[:result] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      else
        disco_path = res[:pvars][:disco_path]
      end

      # disco folder
      disco_folder = File.join(@root_dir, 'disco')

      # run folder
      run_folder = File.join(@root_dir, 'run', @scenario_name.downcase)

      # check of opendss models are created
      opendss_file = File.join(run_folder, 'opendss/dss_files/Master.dss')
      if !File.exist?(opendss_file)
        abort("\nYou must run the OpenDSS analysis before running DISCO. Refer to 'opendss --help' for details on how to run th OpenDSS analysis.")
      end

      if @opthash.subopts[:technical_catalog]
        # users can specify their technical catalogue name, placed in the disco folder
        technical_catalog = @opthash.subopts[:technical_catalog]
      else
        technical_catalog = 'technical_catalog.json'
      end

      # set arguments in config hash
      config_hash = JSON.parse(File.read(File.join(disco_folder, 'config.json')), symbolize_names: true)
      config_hash[:upgrade_cost_database] = File.join(disco_folder, @opthash.subopts[:cost_database]) # Uses default cost database if not specified
      if technical_catalog
        config_hash[:thermal_upgrade_params][:read_external_catalog] = true
        config_hash[:thermal_upgrade_params][:external_catalog] = File.join(disco_folder, technical_catalog)
      end
      config_hash[:jobs][0][:name] = @scenario_name
      config_hash[:jobs][0][:opendss_model_file] = opendss_file

      # save config file in run folder
      File.open(File.join(run_folder, 'config.json'), 'w') { |f| f.write(JSON.pretty_generate(config_hash)) }

      # call disco
      FileUtils.cd(run_folder) do
        if (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM).nil?
          # not windows
          if Dir.exist?(File.join(run_folder, 'disco'))
            # if disco results folder exists overwrite folder
            commands = ["#{disco_path} upgrade-cost-analysis run config.json -o disco --console-log-level=warn --force"]
          else
            commands = ["#{disco_path} upgrade-cost-analysis run config.json -o disco --console-log-level=warn"]
          end
        else
          # windows
          if Dir.exist?(File.join(run_folder, 'disco'))
            # if disco results folder exists overwrite folder)
            commands = ['powershell $env:CONDA_DLL_SEARCH_MODIFICATION_ENABLE = 1', "#{disco_path} upgrade-cost-analysis run config.json -o disco --console-log-level=warn --force"]
          else
            commands = ['powershell $env:CONDA_DLL_SEARCH_MODIFICATION_ENABLE = 1', "#{disco_path} upgrade-cost-analysis run config.json -o disco --console-log-level=warn"]
          end
        end
        puts 'Running DISCO...'
        commands.each do |command|
          # TODO: This will be updated so stderr only reports error/warnings at DISCO level
          stdout, stderr, status = Open3.capture3(command)
          if !stderr.empty?
            puts "ERROR running DISCO: #{stderr}"
          end
        end
        puts "Refer to detailed log file #{File.join(run_folder, 'disco', 'run_upgrade_cost_analysis.log')} for more information on the run."
        puts "Refer to the output summary file #{File.join(run_folder, 'disco', 'output_summary.json')} for a summary of the results."
      end
    end

    # Run RNM Simulation
    if @opthash.command == 'rnm'

      run_dir = File.join(@root_dir, 'run', @scenario_name.downcase)
      # check if project has been post-processed appropriately
      if !File.exist?(File.join(run_dir, 'default_scenario_report.json'))
        abort("\nYou must first post-process the scenario before running RNM.  We recommend 'process --default'.")
      end

      puts 'Preparing RNM inputs'
      # prep arguments
      reopt = @opthash.subopts[:reopt] ? true : false
      opendss_catalog = @opthash.subopts[:opendss] ? true : false

      # if paths below are nil, default paths will be used
      extended_catalog_path = @opthash.subopts[:extended_catalog] || nil
      average_peak_catalog_path = @opthash.subopts[:average_peak_catalog] || nil

      # create inputs, run sim and get results
      begin
        runner = URBANopt::RNM::Runner.new(@scenario_name, run_dir, @opthash.subopts[:scenario], @opthash.subopts[:feature], extended_catalog_path: extended_catalog_path, average_peak_catalog_path: average_peak_catalog_path, reopt: reopt, opendss_catalog: opendss_catalog)
        runner.create_simulation_files
        runner.run
        runner.post_process
      rescue StandardError => e
        abort("\nError: #{e.message}")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end

      # TODO: aggregate back into scenario reports and geojson file
      puts "\nRNM Results saved to: #{File.join(run_dir, 'rnm-us', 'results')}"
      puts "\nDone\n"

    end

    # Post-process the scenario
    if @opthash.command == 'process'
      if @opthash.subopts[:default] == false && @opthash.subopts[:opendss] == false && @opthash.subopts[:reopt_scenario] == false && @opthash.subopts[:reopt_feature] == false && @opthash.subopts[:disco] == false && @opthash.subopts[:reopt_ghp] == false
        abort("\nERROR: No valid process type entered. Must enter a valid process type\n")
      end

      puts 'Post-processing URBANopt results'

      # delete process_status.json
      process_filename = File.join(@root_dir, 'run', @scenario_name.downcase, 'process_status.json')
      FileUtils.rm_rf(process_filename) if File.exist?(process_filename)
      results = []

      default_post_processor = URBANopt::Scenario::ScenarioDefaultPostProcessor.new(run_func)
      scenario_report = default_post_processor.run
      scenario_report.save(file_name = 'default_scenario_report', save_feature_reports: false)
      scenario_report.feature_reports.each(&:save)

      run_dir = File.join(@root_dir, 'run', @scenario_name.downcase)

      if @opthash.subopts[:with_database] == true
        default_post_processor.create_scenario_db_file
      end

      if @opthash.subopts[:default] == true
        puts "\nDone\n"
        results << { process_type: 'default', status: 'Complete', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
      elsif @opthash.subopts[:opendss] == true
        puts "\nPost-processing OpenDSS results\n"
        opendss_folder = File.join(@root_dir, 'run', @scenario_name.downcase, 'opendss')
        if File.directory?(opendss_folder)
          opendss_folder_name = File.basename(opendss_folder)
          opendss_post_processor = URBANopt::Scenario::OpenDSSPostProcessor.new(
            scenario_report,
            opendss_results_dir_name = opendss_folder_name
          )
          opendss_post_processor.run
          puts "\nDone\n"
          results << { process_type: 'opendss', status: 'Complete', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
        else
          results << { process_type: 'opendss', status: 'failed', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
          abort("\nNo OpenDSS results available in folder '#{opendss_folder}'\n")
        end
      elsif @opthash.subopts[:disco] == true
        puts "\nPost-processing DISCO results\n"
        disco_folder = File.join(@root_dir, 'run', @scenario_name.downcase, 'disco')
        if File.directory?(disco_folder)
          disco_folder_name = File.basename(disco_folder)
          disco_post_processor = URBANopt::Scenario::DISCOPostProcessor.new(
            scenario_report,
            disco_results_dir_name = disco_folder_name
          )
          disco_post_processor.run
          puts "\nDone\n"
          results << { process_type: 'disco', status: 'Complete', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
        else
          results << { process_type: 'disco', status: 'failed', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
          abort("\nNo DISCO results available in folder '#{opendss_folder}'\n")
        end
      elsif (@opthash.subopts[:reopt_scenario] == true) || (@opthash.subopts[:reopt_feature] == true)
        # Ensure reopt default files are prepared
        # create_reopt_files(@opthash.subopts[:scenario])

        if @opthash.subopts[:reopt_resilience] == true
          abort('The REopt API is now using open-source optimization solvers; you may experience longer solve times and' \
          ' timeout errors, especially for evaluations with net metering, resilience, and/or 3+ technologies. ' \
          'We will support resilience calculations with the REopt API in a future release.')
        end

        scenario_base = default_post_processor.scenario_base

        # see if reopt-scenario-assumptions-file was passed in, otherwise use the default
        scenario_assumptions = scenario_base.scenario_reopt_assumptions_file
        if @opthash.subopts[:reopt_scenario] == true && @opthash.subopts[:reopt_scenario_assumptions_file]
          scenario_assumptions = File.expand_path(@opthash.subopts[:reopt_scenario_assumptions_file]).to_s
        end

        puts "\nRunning the REopt Scenario post-processor with scenario assumptions file: #{scenario_assumptions}\n"
        # Add community photovoltaic if present in the Feature File
        community_photovoltaic = []
        feature_file = JSON.parse(File.read(File.expand_path(@opthash.subopts[:feature])), symbolize_names: true)
        feature_file[:features].each do |feature|
          if feature[:properties][:district_system_type] && (feature[:properties][:district_system_type] == 'Community Photovoltaic')
            community_photovoltaic << feature
          end
        rescue StandardError => e
          puts "\nERROR: #{e.message}"
        end
        reopt_post_processor = URBANopt::REopt::REoptPostProcessor.new(
          scenario_report,
          scenario_assumptions,
          scenario_base.reopt_feature_assumptions,
          DEVELOPER_NREL_KEY, false
        )
        if @opthash.subopts[:reopt_scenario] == true
          puts "\nPost-processing entire scenario with REopt\n"
          scenario_report_scenario = reopt_post_processor.run_scenario_report(
            scenario_report: scenario_report,
            save_name: 'scenario_optimization',
            run_resilience: @opthash.subopts[:reopt_resilience],
            community_photovoltaic: community_photovoltaic
          )
          results << { process_type: 'reopt_scenario', status: 'Complete', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
          puts "\nDone\n"
        elsif @opthash.subopts[:reopt_feature] == true
          puts "\nPost-processing each building individually with REopt\n"
          # Add groundmount photovoltaic if present in the Feature File
          groundmount_photovoltaic = {}
          feature_file = JSON.parse(File.read(File.expand_path(@opthash.subopts[:feature])), symbolize_names: true)
          feature_file[:features].each do |feature|
            if feature[:properties][:district_system_type] && (feature[:properties][:district_system_type] == 'Ground Mount Photovoltaic')
              groundmount_photovoltaic[feature[:properties][:associated_building_id]] = feature[:properties][:footprint_area]
            end
          rescue StandardError => e
            puts "\nERROR: #{e.message}"
          end
          scenario_report_features = reopt_post_processor.run_scenario_report_features(
            scenario_report: scenario_report,
            save_names_feature_reports: ['feature_optimization'] * scenario_report.feature_reports.length,
            save_name_scenario_report: 'feature_optimization',
            run_resilience: @opthash.subopts[:reopt_resilience],
            keep_existing_output: @opthash.subopts[:reopt_keep_existing],
            groundmount_photovoltaic: groundmount_photovoltaic
          )
          results << { process_type: 'reopt_feature', status: 'Complete', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
          puts "\nDone\n"
        end
      elsif @opthash.subopts[:reopt_ghp] == true

        puts "\nPerforming REopt LCCA Analysis for GHP"

        if @opthash.subopts[:system_parameter].nil? || @opthash.subopts[:modelica_model].nil?
          abort("System Parameter and Modelica Model arguments must be provided to run GHP LCCA analysis.")
        end

        run_dir = File.join(@root_dir, 'run', @scenario_name.downcase)

        # system parameter
        if @opthash.subopts[:system_parameter]
          system_parameter = File.expand_path(@opthash.subopts[:system_parameter])
          loop_order = File.join(File.dirname(system_parameter), '_loop_order_list.json')
          if !File.exist?(loop_order)
            puts "Run the Thermal Network Analysis using --ghe_size prior to running this command"
          end
        end

        # modelica result
        if @opthash.subopts[:modelica_model]
          modelica_model = @opthash.subopts[:modelica_model]
          base_model_name = File.basename(modelica_model)
          modelica_result = File.expand_path(File.join(modelica_model, "#{base_model_name}.Districts.DistrictEnergySystem_results","#{base_model_name}.Districts.DistrictEnergySystem_result.csv"))
          unless File.exist?(modelica_result)
            abort("Modelica results need to be processed using des_process prior to running this commmand")
          end
        end

        # make reopt_ghp folder (if it does not exist)
        reopt_ghp_dir = File.join(@root_dir, 'reopt_ghp')

        unless Dir.exist?(reopt_ghp_dir)
          FileUtils.mkdir_p(reopt_ghp_dir)
          puts "Created directory: #{reopt_ghp_dir}"
        end
        
        # Copy reopt GHP assumptions from CLI example files folder
        $LOAD_PATH.each do |path_item|
          if path_item.to_s.end_with?('example_files')
            reopt_files = File.join(path_item, 'reopt_ghp')
      
            if Dir.exist?(reopt_files)
              Pathname.new(reopt_files).children.each do |reopt_file|
                target_path = File.join(reopt_ghp_dir, reopt_file.basename)
                FileUtils.cp(reopt_file, target_path)
                puts "Copied #{reopt_file} to #{target_path}"
              end
            else
              puts "Directory does not exist: #{reopt_files}"
            end
          end
        end
        

        # see if reopt-scenario-assumptions-file was passed in, otherwise use the default
        reopt_ghp_assumptions = File.join(@root_dir, 'reopt_ghp', 'ghp_assumptions.json')
        if @opthash.subopts[:reopt_ghp_assumptions_file]
          reopt_ghp_assumptions = File.expand_path(@opthash.subopts[:reopt_ghp_assumptions_file]).to_s
        end

        puts "\nRunning the REopt GHP LCCA assumptions file: #{reopt_ghp_assumptions}\n"

        reopt_ghp_post_processor = URBANopt::REopt::REoptGHPPostProcessor.new(
          run_dir,
          system_parameter,
          modelica_model,
          reopt_ghp_assumptions,
          DEVELOPER_NREL_KEY, 
          false
        )

        reopt_ghp_post_processor.run_reopt_lcca(run_dir)

        results << { process_type: 'reopt_ghp', status: 'Complete', timestamp: Time.now.strftime('%Y-%m-%dT%k:%M:%S.%L') }
        puts "\nDone\n"

        
      end

      # write process status file
      File.open(process_filename, 'w') { |f| f.write JSON.pretty_generate(results) }
      
    end

    if @opthash.command == 'visualize'

      if @opthash.subopts[:feature] == false && @opthash.subopts[:scenario] == false
        abort("\nERROR: No valid process type entered. Must enter a valid process type\n")
      end

      if @opthash.subopts[:feature]
        if !@opthash.subopts[:feature].to_s.end_with?('json')
          abort("\nERROR: No Feature File specified. Please specify Feature File for creating scenario visualizations.\n")
        end
        run_dir = File.join(@feature_path, 'run')
        scenario_folders = []
        scenario_report_exists = false
        Dir.glob(File.join(run_dir, '/*_scenario')) do |scenario_folder|
          scenario_report = File.join(scenario_folder, 'scenario_optimization.csv')
          # Check if Scenario Optimization REopt file exists and add that
          if File.exist?(File.join(scenario_folder, 'scenario_optimization.csv'))
            scenario_folders << File.join(scenario_folder, 'scenario_optimization.csv')
            scenario_report_exists = true
          # Check if Default Feature Report exists and add that
          elsif File.exist?(File.join(scenario_folder, 'default_scenario_report.csv'))
            scenario_folders << File.join(scenario_folder, 'default_scenario_report.csv')
            scenario_report_exists = true
          else puts "\nERROR: Default reports not created for #{scenario_folder}. Please use 'process --default' to create default post processing reports for all scenarios first. Visualization not generated for #{scenario_folder}.\n"
          end
        end
        if scenario_report_exists == true
          puts "\nCreating visualizations for all Scenario results\n"
          URBANopt::Scenario::ResultVisualization.create_visualization(scenario_folders, false)
          vis_file_path = File.join(@feature_path, 'visualization')
          if !File.exist?(vis_file_path)
            Dir.mkdir File.join(@feature_path, 'visualization')
          end
          html_in_path = File.join(vis_file_path, 'input_visualization_scenario.html')
          if !File.exist?(html_in_path)
            $LOAD_PATH.each do |path_item|
              if path_item.to_s.end_with?('example_files')
                FileUtils.cp(File.join(path_item, 'visualization', 'input_visualization_scenario.html'), html_in_path)
              end
            end
          end
          html_out_path = File.join(@feature_path, 'run', 'scenario_comparison.html')
          FileUtils.cp(html_in_path, html_out_path)
          puts "\nDone\n"
        end
      end

      if @opthash.subopts[:scenario]
        if !@opthash.subopts[:scenario].to_s.include?('.csv')
          abort("\nERROR: No Scenario File specified. Please specify Scenario File for feature visualizations.\n")
        end
        run_dir = File.join(@root_dir, 'run', @scenario_name.downcase)
        feature_report_exists = false
        csv = CSV.read(File.expand_path(@opthash.subopts[:scenario]), headers: true)
        feature_names = csv['Feature Name']
        feature_folders = []
        # loop through building feature ids from scenario csv
        csv['Feature Id'].each do |feature|
          # Check if Feature Optimization REopt file exists and add that
          if File.exist?(File.join(run_dir, feature, 'feature_reports/feature_optimization.csv'))
            feature_report_exists = true
            feature_folders << File.join(run_dir, feature, 'feature_reports/feature_optimization.csv')
          elsif File.exist?(File.join(run_dir, feature, 'feature_reports/default_feature_report.csv'))
            feature_report_exists = true
            feature_folders << File.join(run_dir, feature, 'feature_reports/default_feature_report.csv')
          else puts "\nERROR: Default reports not created for #{feature}. Please use 'process --default' to create default post processing reports for all features first. Visualization not generated for #{feature}.\n"
          end
        end
        if feature_report_exists == true
          puts "\nCreating visualizations for Feature results in the Scenario\n"
          URBANopt::Scenario::ResultVisualization.create_visualization(feature_folders, true, feature_names)
          vis_file_path = File.join(@root_dir, 'visualization')
          if !File.exist?(vis_file_path)
            Dir.mkdir File.join(@root_dir, 'visualization')
          end
          html_in_path = File.join(vis_file_path, 'input_visualization_feature.html')
          if !File.exist?(html_in_path)
            $LOAD_PATH.each do |path_item|
              if path_item.to_s.end_with?('example_files')
                FileUtils.cp(File.join(path_item, 'visualization', 'input_visualization_feature.html'), html_in_path)
              end
            end
          end
          html_out_path = File.join(@root_dir, 'run', @scenario_name.downcase, 'feature_comparison.html')
          FileUtils.cp(html_in_path, html_out_path)
          puts "\nDone\n"
        end
      end

    end

    # Compare EUI in default_feature_reports.json with a user-editable set of bounds
    if @opthash.command == 'validate'
      puts "\nValidating:"
      if !@opthash.subopts[:eui] && !@opthash.subopts[:foobar]
        abort("\nERROR: No type of validation specified. Please enter a sub-command when using validate.\n")
      end
      # Validate EUI
      if @opthash.subopts[:eui]
        puts 'Energy Use Intensity'
        original_feature_file = JSON.parse(File.read(File.expand_path(@opthash.subopts[:feature])), symbolize_names: true)
        # Build list of paths to each feature in the given Scenario
        feature_ids = CSV.read(@opthash.subopts[:scenario], headers: true)
        feature_list = []
        feature_ids['Feature Id'].each do |feature|
          if Dir.exist?(File.join(@root_dir, 'run', @scenario_name.downcase, feature))
            feature_list << File.join(@root_dir, 'run', @scenario_name.downcase, feature)
          else
            puts "Warning: did not find a directory for FeatureID: #{feature} ...skipping"
          end
        end
        validation_file_name = File.basename(@opthash.subopts[:eui])
        validation_params = YAML.load_file(File.expand_path(@opthash.subopts[:eui]))
        unit_value = validation_params['EUI'][@opthash.subopts[:units]]['Units']
        # Validate EUI for only the features used in the scenario
        original_feature_file[:features].each do |feature| # Loop through each feature in the scenario
          next if !feature_ids['Feature Id'].include? feature[:properties][:id] # Skip features not in the scenario

          feature_list.each do |feature_path| # Match ids in FeatureFile
            next if feature_path.split('/')[-1] != feature[:properties][:id] # Skip until feature ids match

            feature_dir_list = Pathname.new(feature_path).children.select(&:directory?) # Folders in the feature directory
            feature_dir_list.each do |feature_dir|
              next if !File.basename(feature_dir).include? 'default_feature_reports' # Get the folder which can have a variable name

              @json_feature_report = JSON.parse(File.read(File.join(feature_dir, 'default_feature_reports.json')), symbolize_names: true)
            end
            if !@json_feature_report[:reporting_periods][0][:site_EUI_kbtu_per_ft2]
              abort("ERROR: No EUI present. Perhaps you didn't simulate an entire year?")
            end
            case @opthash.subopts[:units]
            when 'IP'
              feature_eui_value = @json_feature_report[:reporting_periods][0][:site_EUI_kbtu_per_ft2]
            when 'SI'
              feature_eui_value = @json_feature_report[:reporting_periods][0][:site_EUI_kwh_per_m2]
            else
              abort("\nERROR: Units type not recognized. Please use a valid option in the CLI")
            end
            building_type = feature[:properties][:building_type] # From FeatureFile
            validation_upper_limit = validation_params['EUI'][@opthash.subopts[:units]][building_type]['max']
            validation_lower_limit = validation_params['EUI'][@opthash.subopts[:units]][building_type]['min']
            if feature_eui_value > validation_upper_limit
              puts "\nFeature #{File.basename(feature_path)} (#{building_type}) EUI of #{feature_eui_value.round(2)} #{unit_value} " \
              "is greater than the validation maximum of #{validation_upper_limit}."
            elsif feature_eui_value < validation_lower_limit
              puts "\nFeature #{File.basename(feature_path)} (#{building_type}) EUI of #{feature_eui_value.round(2)} #{unit_value} " \
              "is less than the validation minimum of #{validation_lower_limit}."
            else
              puts "\nFeature #{File.basename(feature_path)} (#{building_type}) EUI of #{feature_eui_value.round(2)} #{unit_value} " \
              "is within bounds set by #{validation_file_name} (#{validation_lower_limit} - #{validation_upper_limit})."
            end
          end
        end
      end
    end

    if @opthash.command == 'des_params'

      # first check python
      res = check_python
      if res[:python] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      end

      des_cli_root = "#{res[:pvars][:gmt_path]} build-sys-param"
      if @opthash.subopts[:sys_param]
        des_cli_addition = " #{@opthash.subopts[:sys_param]}"
        if @opthash.subopts[:scenario]
          des_cli_addition += " #{@opthash.subopts[:scenario]}"
        end
        if @opthash.subopts[:feature]
          des_cli_addition += " #{@opthash.subopts[:feature]}"
        end
        if @opthash.subopts[:district_type]
          run_dir = @root_dir / 'run' / @scenario_name.downcase
          ghe_run_dir = run_dir / 'ghe_dir'
          # make ghe run dir
          unless Dir.exist?(ghe_run_dir)
            Dir.mkdir ghe_run_dir
            puts "Creating GHE results folder #{ghe_run_dir}"
          end
          des_cli_addition += " #{@opthash.subopts[:district_type]}"
        end
        if @opthash.subopts[:model_type]
          des_cli_addition += " #{@opthash.subopts[:model_type]}"
        end
        if @opthash.subopts[:overwrite]
          puts "\nDeleting and rebuilding existing sys-param file"
          des_cli_addition += ' --overwrite'
        end
      else
        abort("\nCommand must include new system parameter file name, ScenarioFile, & FeatureFile. Please try again")
      end
      begin
        system(des_cli_root + des_cli_addition)
      rescue FileNotFoundError
        abort("\nMust simulate using 'uo run' before preparing Modelica models.")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end
    end

    if @opthash.command == 'des_create'

      # first check python
      res = check_python
      if res[:python] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      end

      des_cli_root = "#{res[:pvars][:gmt_path]} create-model"
      if @opthash.subopts[:sys_param]
        des_cli_addition = " #{@opthash.subopts[:sys_param]}"
        if @opthash.subopts[:feature]
          des_cli_addition += " #{@opthash.subopts[:feature]}"
        end
        if @opthash.subopts[:des_name]
          des_cli_addition += " #{File.expand_path(@opthash.subopts[:des_name])}"
        end
        if @opthash.subopts[:overwrite]
          puts "\nDeleting and rebuilding existing Modelica dir"
          des_cli_addition += ' --overwrite'
        end
      else
        abort("\nCommand must include system parameter file name and FeatureFile. Please try again")
      end
      begin
        system(des_cli_root + des_cli_addition)
      rescue FileNotFoundError
        abort("\nMust simulate using 'uo run' before preparing Modelica models.")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end
    end

    if @opthash.command == 'des_run'

      # first check python
      res = check_python
      if res[:python] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      end

      des_cli_root = "#{res[:pvars][:gmt_path]} run-model"
      if @opthash.subopts[:model]
        des_cli_addition = " #{File.expand_path(@opthash.subopts[:model])}"
        if @opthash.subopts[:start_time]
          des_cli_addition += " -a #{@opthash.subopts[:start_time]}"
        end
        if @opthash.subopts[:stop_time]
          des_cli_addition += " -z #{@opthash.subopts[:stop_time]}"
        end
        if @opthash.subopts[:step_size]
          des_cli_addition += " -x #{@opthash.subopts[:step_size]}"
        end
        if @opthash.subopts[:interval]
          des_cli_addition += " -i #{@opthash.subopts[:interval]}"
        end
      else
        abort("\nCommand must include Modelica model name. Please try again")
      end
      
      begin
        system(des_cli_root + des_cli_addition)  
      rescue FileNotFoundError
        abort("\nMust simulate using 'uo run' before preparing Modelica models.")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end
    end

    if @opthash.command == 'des_process'
      # first check python
      res = check_python
      if res[:python] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      end
      des_cli_root = "#{res[:pvars][:gmt_path]} process-model"
      if @opthash.subopts[:model]
          des_cli_addition = " #{@opthash.subopts[:model]}"
      else
        abort("\nCommand must include Modelica model name. Please try again")
      end
      begin
        system(des_cli_root + des_cli_addition)
      rescue FileNotFoundError
        abort("\nMust simulate using 'uo run' before preparing Modelica models.")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end
    end

    if @opthash.command == 'ghe_size'

      # first check python
      res = check_python
      if res[:python] == false
        puts "\nPython error: #{res[:message]}"
        abort("\nPython dependencies are needed to run this workflow. Install with the CLI command: uo install_python  \n")
      end

      ghe_cli_root = res[:pvars][:ghe_path].to_s

      if @opthash.subopts[:sys_param]
        ghe_cli_addition = " -y #{@opthash.subopts[:sys_param]}"

        if @opthash.subopts[:scenario]
          # GHE cli needs the scenario folder name
          root_dir, scenario_file_name = Pathname(File.expand_path(@opthash.subopts[:scenario])).split
          scenario_name = File.basename(scenario_file_name, File.extname(scenario_file_name))
          run_dir = root_dir / 'run' / scenario_name.downcase
          ghe_run_dir = run_dir / 'ghe_dir'
          unless Dir.exist?(ghe_run_dir)
            Dir.mkdir ghe_run_dir
            puts "Creating GHE results folder #{ghe_run_dir}"
          end
          ghe_cli_addition += " -s #{run_dir}"
          ghe_cli_addition += " -o #{ghe_run_dir}"
        end

        if @opthash.subopts[:feature]
          ghe_cli_addition += " -f #{@opthash.subopts[:feature]}"
        end

      else
        abort("\nCommand must include ScenarioFile & FeatureFile. Please try again")
      end
      # if @opthash.subopts[:verbose]
      #   puts "ghe_cli_root: #{ghe_cli_root}"
      #   puts "ghe_cli_addition: #{ghe_cli_addition}"
      #   puts "command: #{ghe_cli_root + ghe_cli_addition}"
      # end
      begin
        system(ghe_cli_root + ghe_cli_addition)
      rescue FileNotFoundError
        abort("\nFile Not Found Error Holder.")
      rescue StandardError => e
        puts "\nERROR: #{e.message}"
      end

    end

    # Delete simulations from a scenario
    if @opthash.command == 'delete'
      scenario_results_dir = File.join(@root_dir, 'run', @scenario_name.downcase)
      puts "\nDeleting previous results from '#{@scenario_name}'...\n"
      FileUtils.rm_rf(scenario_results_dir)
      puts "\nDone\n"
    end
  end
end
