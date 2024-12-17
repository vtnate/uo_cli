# *********************************************************************************
# URBANopt (tm), Copyright (c) Alliance for Sustainable Energy, LLC.
# See also https://github.com/urbanopt/urbanopt-cli/blob/develop/LICENSE.md
# *********************************************************************************

require 'csv'
require 'json'
require 'open3'
require 'fileutils'

RSpec.describe URBANopt::CLI do
  example_dir = Pathname(__FILE__).dirname.parent / 'example_files'
  spec_dir = Pathname(__FILE__).dirname
  test_directory = spec_dir / 'test_directory'
  test_directory_res = spec_dir / 'test_directory_res'
  test_directory_res_hpxml = spec_dir / 'test_directory_res_hpxml'
  test_directory_elec = spec_dir / 'test_directory_elec'
  test_directory_disco = spec_dir / 'test_directory_disco'
  test_directory_pv = spec_dir / 'test_directory_pv'
  test_directory_ghe = spec_dir / 'test_directory_ghe'
  test_scenario = test_directory / 'two_building_scenario.csv'
  test_scenario_res = test_directory_res / 'two_building_res'
  test_scenario_res_hpxml = test_directory_res_hpxml / 'two_building_res_hpxml.csv'
  test_scenario_reopt = test_directory_pv / 'REopt_scenario.csv'
  test_scenario_pv = test_directory_pv / 'two_building_scenario.csv'
  test_scenario_elec = test_directory_elec / 'electrical_scenario.csv'
  test_scenario_disco = test_directory_disco / 'electrical_scenario.csv'
  test_scenario_ev = test_directory / 'two_building_ev_scenario.csv'
  test_scenario_chilled = test_directory_res / 'two_building_chilled.csv'
  test_scenario_mels_reduction = test_directory_res / 'two_building_mels_reduction.csv'
  test_scenario_stat_adjustment = test_directory_res / 'two_building_stat_adjustment.csv'
  test_scenario_flexible_hot_water = test_directory / 'two_building_flexible_hot_water.csv'
  test_scenario_thermal_storage = test_directory / 'two_building_thermal_storage.csv'
  test_scenario_ghe = test_directory_ghe / 'baseline_scenario_ghe.csv'
  test_feature = test_directory / 'example_project.json'
  test_feature_res = test_directory_res / 'example_project_combined.json'
  test_feature_elec = test_directory_elec / 'example_project_with_electric_network.json'
  test_feature_disco = test_directory_disco / 'example_project_with_electric_network.json'
  test_feature_pv = test_directory_pv / 'example_project_with_PV.json'
  test_feature_rnm = test_directory / 'example_project_with_streets.json'
  test_feature_ghe = test_directory_ghe / 'example_project_with_ghe.json'
  test_validate_bounds = test_directory_res / 'out_of_bounds_validation.yaml'
  test_reopt_scenario_assumptions_file = test_directory_pv / 'reopt' / 'multiPV_assumptions.json'
  system_parameters_file = test_directory / 'run' / 'two_building_scenario' / 'system_parameter.json'
  ghe_system_parameters_file = test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'ghe_system_parameter.json'
  test_weather_file = test_directory_res / 'weather' / 'USA_NY_Buffalo-Greater.Buffalo.Intl.AP.725280_TMY3.epw'
  call_cli = 'bundle exec uo'

  # Ensure clean slate for testing
  # +dir_or_file+ string - path to a file or folder
  def delete_directory_or_file(dir_or_file)
    if File.exist?(dir_or_file)
      FileUtils.rm_rf(dir_or_file)
      puts "Deleted #{dir_or_file} during test preparation"
    end
  end

  # Find Python version
  # Returns Python version as a list of strings for major, minor, and patch
  def find_python_version
    version_output, status = Open3.capture2e('python3 --version')
    if status.success?
      version = version_output.split(' ')[1]
      return version.split('.')
    end
  end

  # Look through the workflow file and activate certain measures
  # params\
  # +test_dir+:: _path_ Path to the test directory being used
  # +measure_name_list+:: _array_ Measure dir_names - present in the named workflow file
  # +workflow+:: _string_ Name of the workflow file (found in project_dir/mappers) to search for measures
  #
  # This function toggles the __SKIP__ argument of measures
  def select_measures(test_dir, measure_name_list, workflow = 'base_workflow.osw', skip_setting: false)
    # FIXME: More clear argument name than `skip_setting`. It is changing the value of the __SKIP__ argument in the measure.
    base_workflow_path = test_dir / 'mappers' / workflow
    base_workflow_hash = JSON.parse(File.read(base_workflow_path))
    base_workflow_hash['steps'].each do |measure|
      if measure_name_list.include? measure['measure_dir_name']
        measure['arguments']['__SKIP__'] = skip_setting
      end
      File.open(base_workflow_path, 'w+') do |f|
        f << base_workflow_hash.to_json
      end
    end
  end

  context 'Admin' do
    it 'displays the correct version number' do
      expect { system("#{call_cli} --version") }
        .to output(a_string_including(URBANopt::CLI::VERSION))
        .to_stdout_from_any_process
    end

    it 'returns help' do
      expect { system("#{call_cli} --help") }
        .to output(a_string_including('Commands:'))
        .to_stdout_from_any_process
    end

    it 'returns help for a specific command' do
      expect { system("#{call_cli} create --help") }
        .to output(a_string_including('Create project directory'))
        .to_stdout_from_any_process
    end

    it 'returns graceful error message if dir passed to "create -s" command' do
      unless test_directory.exist?
        system("#{call_cli} create --project-folder #{test_directory}")
      end
      expect { system("#{call_cli} create -s #{test_directory}") }
        .to output(a_string_including('is a directory.'))
        .to_stderr_from_any_process
    end

    it 'returns graceful error message if non-json file passed to create -s command' do
      unless test_directory.exist?
        system("#{call_cli} create --project-folder #{test_directory}")
      end
      expect { system("#{call_cli} create -s #{test_directory}/validation_schema.yaml") }
        .to output(a_string_including("didn't provide a json file."))
        .to_stderr_from_any_process
    end

    it 'returns graceful error message if invalid json file passed to create -s command' do
      unless test_directory.exist?
        system("#{call_cli} create --project-folder #{test_directory}")
      end
      expect { system("#{call_cli} create -s #{test_directory}/runner.conf") }
        .to output(a_string_including("didn't provide a valid feature_file."))
        .to_stderr_from_any_process
    end

    it 'returns graceful error when no command given' do
      expect { system(call_cli) }
        .to output(a_string_including('Invalid command'))
        .to_stderr_from_any_process
    end

    it 'returns graceful error when invalid command given' do
      expect { system("#{call_cli} asdf") }
        .to output(a_string_including('Invalid command'))
        .to_stderr_from_any_process
    end

    it 'returns graceful error if no is flag passed to `create` command' do
      expect { system("#{call_cli} create #{test_directory}") }
        .to output(a_string_including('No options provided'))
        .to_stderr_from_any_process
    end
  end

  context 'Create project' do
    before :each do
      delete_directory_or_file(test_directory)
      delete_directory_or_file(test_directory_res)
      delete_directory_or_file(test_directory_elec)
      delete_directory_or_file(test_directory_disco)
      delete_directory_or_file(test_directory_pv)
      delete_directory_or_file(test_directory_ghe)
    end

    it 'creates an example project directory' do
      system("#{call_cli} create --project-folder #{test_directory}")
      expect(test_feature.exist?).to be true
      expect((test_directory / 'mappers' / 'Baseline.rb').exist?).to be true
    end

    it 'creates an example project directory when create bar geometry method specified' do
      system("#{call_cli} create --project-folder #{test_directory} --create-bar")
      expect((test_directory / 'mappers' / 'CreateBar.rb').exist?).to be true
      expect((test_directory / 'mappers' / 'createbar_workflow.osw').exist?).to be true
    end

    it 'creates an example project directory when floorspace method specified' do
      system("#{call_cli} create --project-folder #{test_directory} --floorspace")
      expect((test_directory / 'mappers' / 'Floorspace.rb').exist?).to be true
      expect((test_directory / 'example_floorspace_project.json').exist?).to be true
    end

    it 'creates an example project directory for combined residential and commercial workflow' do
      system("#{call_cli} create --project-folder #{test_directory_res} --combined")
      expect((test_directory_res / 'mappers' / 'residential').exist?).to be true
      expect(test_feature_res.exist?).to be true
      expect((test_directory_res / 'measures').exist?).to be true
      expect((test_directory_res / 'resources').exist?).to be true
    end

    it 'creates an example project directory with electrical network properties' do
      system("#{call_cli} create --project-folder #{test_directory_elec} --electric")
      expect(test_feature_elec.exist?).to be true
    end

    it 'creates an example project directory with electrical network properties and disco workflow' do
      system("#{call_cli} create --project-folder #{test_directory_disco} --disco")
      expect(test_feature_disco.exist?).to be true
    end

    it 'creates an example project directory with PV' do
      system("#{call_cli} create --project-folder #{test_directory_pv} --photovoltaic")
      expect(test_feature_pv.exist?).to be true
    end

    it 'creates an example project directory for rnm workflow' do
      system("#{call_cli} create --project-folder #{test_directory} --streets")
      expect(test_feature_rnm.exist?).to be true
    end

    it 'creates an example project directory for ghe workflow' do
      system("#{call_cli} create --project-folder #{test_directory_ghe} --ghe")
      expect(test_feature_ghe.exist?).to be true
    end

    it 'creates an empty project directory' do
      system("#{call_cli} create --empty --project-folder #{test_directory}")
      expect(test_feature.exist?).to be false
      expect((test_directory / 'mappers' / 'Baseline.rb').exist?).to be true
    end

    it 'does not overwrite a project directory without --overwrite' do
      system("#{call_cli} create --project-folder #{test_directory}")
      expect(test_feature.exist?).to be true
      expect { system("#{call_cli} create --project-folder #{test_directory}") }
        .to output(a_string_including('already a directory at'))
        .to_stderr_from_any_process
    end

    it 'overwrites a project directory with --overwrite' do
      system("#{call_cli} create --project-folder #{test_directory}")
      expect(test_feature.exist?).to be true
      expect { system("#{call_cli} create --overwrite --project-folder #{test_directory}") }
        .to output(a_string_including('Overwriting'))
        .to_stdout_from_any_process
      expect(test_feature.exist?).to be true
    end

    it 'overwrites an existing project directory with an empty directory' do
      system("#{call_cli} create --project-folder #{test_directory}")
      expect(test_feature.exist?).to be true
      system("#{call_cli} create --empty --overwrite --project-folder #{test_directory}")
      expect(test_feature.exist?).to be false
      expect((test_directory / 'mappers' / 'Baseline.rb').exist?).to be true
    end

    it 'sets num_parallel on project creation with env var' do
      orig_env_val = ENV['UO_NUM_PARALLEL'] if ENV['UO_NUM_PARALLEL']
      ENV['UO_NUM_PARALLEL'] = '3'
      expect(ENV['UO_NUM_PARALLEL']).to eq('3')
      system("#{call_cli} create --project-folder #{test_directory}")
      runner_file_path = test_directory / 'runner.conf'
      runner_conf_hash = JSON.parse(File.read(runner_file_path))
      expect(runner_conf_hash['num_parallel']).to eq(3)
      # Reset back to original value after test completion
      ENV['UO_NUM_PARALLEL'] = orig_env_val
    end
  end

  context 'Make and manipulate ScenarioFiles' do
    before :all do
      delete_directory_or_file(test_directory)
      system("#{call_cli} create --project-folder #{test_directory}")
    end

    it 'creates a scenario file from a feature file' do
      expect((test_directory / 'baseline_scenario.csv').exist?).to be false
      system("#{call_cli} create --scenario-file #{test_feature}")
      expect((test_directory / 'baseline_scenario.csv').exist?).to be true
      expect((test_directory / 'evcharging_scenario.csv').exist?).to be true
    end

    it 'creates a scenario file for a single feature from a feature file' do
      expect((test_directory / 'baseline_scenario-2.csv').exist?).to be false
      system("#{call_cli} create --scenario-file #{test_feature} --single-feature 2")
      expect((test_directory / 'baseline_scenario-2.csv').exist?).to be true
    end
  end

  context 'Update project directory' do
    before :all do
      delete_directory_or_file(test_directory)
      system("#{call_cli} create --project-folder #{test_directory}")
      delete_directory_or_file(test_directory_res)
      system("#{call_cli} create --project-folder #{test_directory_res} --combined")
      delete_directory_or_file(test_directory_elec)
      system("#{call_cli} create --project-folder #{test_directory_elec} --electric")
    end

    it 'can update project directory' do
      system("#{call_cli} update --existing-project-folder #{test_directory} --new-project-directory #{spec_dir / 'new_test_directory'}")
      expect((spec_dir / 'new_test_directory' / 'mappers').exist?).to be true
      expect((spec_dir / 'new_test_directory' / 'example_project.json').exist?).to be true

      system("#{call_cli} update --existing-project-folder #{test_directory_res} --new-project-directory #{spec_dir / 'new_test_directory_resi'}")
      expect((spec_dir / 'new_test_directory_resi' / 'mappers' / 'residential').exist?).to be true

      system("#{call_cli} update --existing-project-folder #{test_directory_elec} --new-project-directory #{spec_dir / 'new_test_directory_ele'}")
      expect((spec_dir / 'new_test_directory_ele' / 'opendss').exist?).to be true

      delete_directory_or_file(spec_dir / 'new_test_directory')
      delete_directory_or_file(spec_dir / 'new_test_directory_resi')
      delete_directory_or_file(spec_dir / 'new_test_directory_ele')
    end
  end

  context 'Install python dependencies' do
    it 'successfully installs python and dependencies' do
      config = example_dir / 'python_deps' / 'config.json'
      FileUtils.rm_rf(config) if config.exist?
      system("#{call_cli} install_python")
      python_config = example_dir / 'python_deps' / 'python_config.json'
      expect(python_config.exist?).to be true

      configs = JSON.parse(File.read(python_config))
      expect(configs['python_path']).not_to be_falsey
      expect(configs['pip_path']).not_to be_falsey
      expect(configs['ditto_path']).not_to be_falsey
      expect(configs['gmt_path']).not_to be_falsey
      expect(configs['disco_path']).not_to be_falsey
      expect(configs['ghe_path']).not_to be_falsey
    end
  end

  context 'Run and work with a small basic simulation' do
    before :all do
      delete_directory_or_file(test_directory)
      system("#{call_cli} create --project-folder #{test_directory}")
    end

    it 'runs a 2 building scenario using default geometry method', :basic do
      # Use a ScenarioFile with only 2 buildings to reduce test time
      system("cp #{spec_dir / 'spec_files' / 'two_building_scenario.csv'} #{test_scenario}")
      system("#{call_cli} run --scenario #{test_scenario} --feature #{test_feature}")
      expect((test_directory / 'run' / 'two_building_scenario' / '2' / 'failed.job').exist?).to be false
      expect((test_directory / 'run' / 'two_building_scenario' / '2' / 'finished.job').exist?).to be true
      expect((test_directory / 'run' / 'two_building_scenario' / '3' / 'finished.job').exist?).to be false
    end

    it 'runs a 2 building scenario using create bar geometry method', :basic do
      # Copy create bar specific files
      system("cp #{example_dir / 'mappers' / 'CreateBar.rb'} #{test_directory / 'mappers' / 'CreateBar.rb'}")
      system("cp #{example_dir / 'mappers' / 'createbar_workflow.osw'} #{test_directory / 'mappers' / 'createbar_workflow.osw'}")
      system("cp #{spec_dir / 'spec_files' / 'two_building_create_bar.csv'} #{test_directory / 'two_building_create_bar.csv'}")
      system("#{call_cli} run --scenario #{test_directory / 'two_building_create_bar.csv'} --feature #{test_feature}")
      expect((test_directory / 'run' / 'two_building_create_bar' / '2' / 'finished.job').exist?).to be true
    end

    it 'runs a 2 building scenario using floorspace geometry method', :basic do
      # Copy floorspace specific files
      system("cp #{example_dir / 'mappers' / 'Floorspace.rb'} #{test_directory / 'mappers' / 'Floorspace.rb'}")
      system("cp #{example_dir / 'mappers' / 'floorspace_workflow.osw'} #{test_directory / 'mappers' / 'floorspace_workflow.osw'}")
      system("cp #{example_dir / 'osm_building' / '7_floorspace.json'} #{test_directory / 'osm_building' / '7_floorspace.json'}")
      system("cp #{example_dir / 'osm_building' / '7_floorspace.osm'} #{test_directory / 'osm_building' / '7_floorspace.osm'}")
      system("cp #{example_dir / 'example_floorspace_project.json'} #{test_directory / 'example_floorspace_project.json'}")
      system("cp #{spec_dir / 'spec_files' / 'two_building_floorspace.csv'} #{test_directory / 'two_building_floorspace.csv'}")
      expect((test_directory / 'osm_building' / '7_floorspace.osm').exist?).to be true
      system("#{call_cli} run --scenario #{test_directory / 'two_building_floorspace.csv'} --feature #{test_directory / 'example_floorspace_project.json'}")
      expect((test_directory / 'run' / 'two_building_floorspace' / '5' / 'finished.job').exist?).to be true
      expect((test_directory / 'run' / 'two_building_floorspace' / '7' / 'finished.job').exist?).to be true
    end

    it 'runs an ev-charging scenario', :basic do
      # copy ev-charging specific files
      system("cp #{spec_dir / 'spec_files' / 'two_building_ev_scenario.csv'} #{test_scenario_ev}")
      system("#{call_cli} run --scenario #{test_scenario_ev} --feature #{test_feature}")
      expect((test_directory / 'run' / 'two_building_ev_scenario' / '5' / 'finished.job').exist?).to be true
      expect((test_directory / 'run' / 'two_building_ev_scenario' / '2' / 'finished.job').exist?).to be true
    end

    it 'post-processor closes gracefully if given an invalid type', :basic do
      # Type is totally random
      expect { system("#{call_cli} process --foobar --scenario #{test_scenario} --feature #{test_feature}") }
        .to output(a_string_including("unknown argument '--foobar'"))
        .to_stderr_from_any_process
      # Type is valid, but with extra characters
      expect { system("#{call_cli} process --reopt-scenariot --scenario #{test_scenario} --feature #{test_feature}") }
        .to output(a_string_including("unknown argument '--reopt-scenariot'"))
        .to_stderr_from_any_process
      # Type would be valid if not missing characters
      expect { system("#{call_cli} process --reopt-scenari --scenario #{test_scenario} --feature #{test_feature}") }
        .to output(a_string_including("unknown argument '--reopt-scenari'"))
        .to_stderr_from_any_process
    end

    it 'post-processor closes gracefully if not given a type', :basic do
      expect { system("#{call_cli} process --scenario #{test_scenario} --feature #{test_feature}") }
        .to output(a_string_including('No valid process type entered'))
        .to_stderr_from_any_process
    end

    it 'default post-processes a scenario', :basic do
      # This test requires the 'runs a 2 building scenario using default geometry method' be run first
      test_scenario_report = test_directory / 'run' / 'two_building_scenario' / 'default_scenario_report.csv'
      system("#{call_cli} process --default --scenario #{test_scenario} --feature #{test_feature}")
      expect(`wc -l < #{test_scenario_report}`.to_i).to be > 2
      expect((test_directory / 'run' / 'two_building_scenario' / 'process_status.json').exist?).to be true
    end

    it 'successfully runs the rnm workflow', :basic do
      # This test requires the 'runs a 2 building scenario using default geometry method' be run first
      # copy featurefile in dir
      rnm_file = 'example_project_with_streets.json'
      system("cp #{spec_dir / 'spec_files' / rnm_file} #{test_directory / rnm_file}")
      # call rnm
      test_rnm_file = test_directory / rnm_file
      system("#{call_cli} rnm --scenario #{test_scenario} --feature #{test_rnm_file}")
      # check that rnm inputs and outputs were created
      expect((test_directory / 'run' / 'two_building_scenario' / 'rnm-us' / 'inputs.zip').exist?).to be true
      expect((test_directory / 'run' / 'two_building_scenario' / 'rnm-us' / 'results').exist?).to be true
      expect((test_directory / 'run' / 'two_building_scenario' / 'scenario_report_rnm.json').exist?).to be true
      expect((test_directory / 'run' / 'two_building_scenario' / 'feature_file_rnm.json').exist?).to be true
    end

    it 'saves post-process output as a database file', :basic do
      # This test requires the 'runs a 2 building scenario using default geometry method' be run first
      db_filename = test_directory / 'run' / 'two_building_scenario' / 'default_scenario_report.db'
      system("#{call_cli} process --default --with-database --scenario #{test_scenario} --feature #{test_feature}")
      expect(`wc -l < #{db_filename}`.to_i).to be > 20
      expect((test_directory / 'run' / 'two_building_scenario' / 'process_status.json').exist?).to be true
    end

    it 'creates scenario visualization for default post processor', :basic do
      # This test requires the 'runs a 2 building scenario using default geometry method' be run first
      # visualizing via the FeatureFile will throw error to stdout (but not crash) if a scenario that uses those features isn't processed first.
      system("#{call_cli} process --default --scenario #{test_scenario} --feature #{test_feature}")
      system("#{call_cli} process --default --scenario #{test_scenario_ev} --feature #{test_feature}")
      system("#{call_cli} visualize --feature #{test_feature}")
      expect((test_directory / 'run' / 'scenario_comparison.html').exist?).to be true
    end

    it 'creates feature visualization for default post processor', :basic do
      # This test requires the 'runs a 2 building scenario using default geometry method' be run first
      system("#{call_cli} process --default --scenario #{test_scenario} --feature #{test_feature}")
      system("#{call_cli} visualize --scenario #{test_scenario}")
      expect((test_directory / 'run' / 'two_building_scenario' / 'feature_comparison.html').exist?).to be true
    end

    it 'ensures viz files are in the project directory', :basic do
      # This test requires the 'runs a 2 building scenario using default geometry method' be run first
      if (test_directory / 'visualization' / 'input_visualization_feature.html').exist?
        FileUtils.rm_rf(test_directory / 'visualization' / 'input_visualization_feature.html')
      end
      if (test_directory / 'run' / 'two_building_scenario' / 'feature_comparison.html').exist?
        FileUtils.rm_rf(test_directory / 'run' / 'two_building_scenario' / 'feature_comparison.html')
      end
      if (test_directory / 'run' / 'two_building_scenario' / 'scenarioData.js').exist?
        FileUtils.rm_rf(test_directory / 'run' / 'two_building_scenario' / 'scenarioData.js')
      end
      expect((test_directory / 'visualization' / 'input_visualization_feature.html').exist?).to be false
      expect((test_directory / 'run' / 'two_building_scenario' / 'feature_comparison.html').exist?).to be false
      expect((test_directory / 'run' / 'two_building_scenario' / 'scenarioData.js').exist?).to be false
      system("#{call_cli} visualize --scenario #{test_scenario}")
      expect((test_directory / 'run' / 'two_building_scenario' / 'feature_comparison.html').exist?).to be true
    end

    it 'deletes a scenario', :basic do
      expect((test_directory / 'run' / 'two_building_create_bar' / '2' / 'data_point_out.json').exist?).to be true
      bar_scenario = test_directory / 'two_building_create_bar.csv'
      system("#{call_cli} delete --scenario #{bar_scenario}")
      expect((test_directory / 'run' / 'two_building_create_bar' / '2' / 'data_point_out.json').exist?).to be false
    end
  end

  context 'Run and work with a small GHE simulation' do
    before :all do
      delete_directory_or_file(test_directory_ghe)
      system("#{call_cli} create --project-folder #{test_directory_ghe} --ghe")
    end

    it 'runs a ghe project', :ghe do
      FileUtils.cp(spec_dir / 'spec_files' / 'baseline_scenario_ghe.csv', test_scenario_ghe)
      expect((test_scenario_ghe).exist?).to be true
      puts "copied #{test_scenario_ghe}"
      system("#{call_cli} run --scenario #{test_scenario_ghe} --feature #{test_feature_ghe}")
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / '4' / 'finished.job').exist?).to be true
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / '5' / 'finished.job').exist?).to be true
    end

    it 'default post-processes ghe scenario', :ghe do
      # This test requires the 'run ghe project' be run first
      test_scenario_report = test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'default_scenario_report.csv'
      system("#{call_cli} process --default --scenario #{test_scenario_ghe} --feature #{test_feature_ghe}")
      # expect(`wc -l < #{test_scenario_report}`.to_i).to be > 2
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'process_status.json').exist?).to be true
    end

    it 'creates a system parameter file with GHE properties', :ghe do
      system("#{call_cli} des_params --scenario #{test_scenario_ghe} --feature #{test_feature_ghe} --sys-param #{ghe_system_parameters_file} --district-type 5G_ghe")
      expect(ghe_system_parameters_file.exist?).to be true
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'ghe_dir').exist?).to be true
    end

    it 'overwrites a system parameter file', :ghe do
      expect(ghe_system_parameters_file.exist?).to be true
      system("#{call_cli} des_params --scenario #{test_scenario_ghe} --feature #{test_feature_ghe} --sys-param #{ghe_system_parameters_file} --district-type 5G_ghe --overwrite")
      expect(ghe_system_parameters_file.exist?).to be true
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'ghe_dir').exist?).to be true
    end

    it 'successfully calls the Thermal Network repository for GHE Sizing', :ghe do
      system("#{call_cli} ghe_size --sys-param #{ghe_system_parameters_file} --scenario #{test_scenario_ghe} --feature #{test_feature_ghe}")
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'ghe_dir').exist?).to be true
      expect((test_directory_ghe / 'run' / 'baseline_scenario_ghe' / 'ghe_dir').empty?).to be false
    end

    it 'creates a 5G Modelica model with the GMT', :ghe do
      system("#{call_cli} des_create --feature #{test_feature_ghe} --sys-param #{ghe_system_parameters_file} --des-name #{test_directory_ghe / 'modelica_ghe'} --district_type 5G_ghe")
      expect((test_directory_ghe / 'modelica_ghe' / 'Districts' / 'DistrictEnergySystem.mo').exist?).to be true
    end

    it 'overwrites an existing 5G Modelica model', :ghe do
      system("#{call_cli} des_create --feature #{test_feature_ghe} --sys-param #{ghe_system_parameters_file} --des-name #{test_directory_ghe / 'modelica_ghe'} --overwrite")
      expect((test_directory_ghe / 'modelica_ghe' / 'Districts' / 'DistrictEnergySystem.mo').exist?).to be true
    end

    it 'runs a Modelica simulation with the GMT', :ghe do
      skip('Requires Docker to be installed') unless system('which docker > /dev/null 2>&1')
      system("#{call_cli} des_run --model #{test_directory_ghe / 'modelica_ghe'}")
      expect((test_directory_ghe / 'modelica_ghe' / 'modelica_ghe.Districts.DistrictEnergySystem_results' / 'modelica_ghe.Districts.DistrictEnergySystem_res.mat').exist?).to be true
    end
  end

  context 'Run REopt LCCA analysis for a GHE network' do

    it 'can run a REopt LCCA analysis' do
      reopt_dir = File.join(spec_dir, 'reopt_ghp')
      system_parameter = File.join(reopt_dir, 'system_parameter_ghe_2feature.json')
      modelica_model = File.join(reopt_dir, 'modelica_4')
      feature_file = File.join(reopt_dir, 'example_project_with_ghe_2features.json')
      scenario_file = File.join(reopt_dir, 'baseline_scenario_ghe.csv')
      puts system_parameter
      puts modelica_model
      FileUtils.cp_r(spec_dir / 'spec_files' / 'reopt_ghp', spec_dir)
      
      system("#{call_cli} process --reopt-ghp --system-parameter #{system_parameter} --modelica-model #{modelica_model} --scenario #{scenario_file} --feature #{feature_file}")
      reopt_inputs = File.join(reopt_dir,'run', 'baseline_scenario_ghe', 'reopt_ghp','reopt_ghp_inputs')
      expect(Dir.exist?(reopt_inputs)).to be true
      reopt_outputs = File.join(reopt_dir,'run', 'baseline_scenario_ghe', 'reopt_ghp','reopt_ghp_outputs')
      expect(Dir.exist?(reopt_inputs)).to be true
      expect(Dir.empty?(reopt_inputs)).to be false
      # TODO : Uncomment after GHX outputs are resolved
      # Dir.foreach(reopt_ghp_output) do |file|
      #     next if file == '.' || file == '..' # Skip current and parent directory references
      #     file_path = File.join(reopt_ghp_output, file)
        
      #     if File.file?(file_path)
      #         File.open(file_path, 'r') do |f|
      #             file_data = JSON.parse(f.read, symbolize_names: true)
      #             expect(file_data[:outputs][:Financial][:npv]).to_not be_nil
      #             expect(file_data[:outputs][:Financial][:lcc]).to_not be_nil
      #             expect(file_data[:messages][:errors]).to be_nil.or be_empty
      #         end
      #     end
      # end
      output_building_5 = File.join(reopt_outputs, 'GHP_building_5_output.json')
      output_building_5_data = nil
      File.open(output_building_5, 'r') do |f|
          output_building_5_data = JSON.parse(f.read, symbolize_names: true)
          expect(output_building_5_data[:outputs][:Financial][:npv]).to_not be_nil
          expect(output_building_5_data[:outputs][:Financial][:lcc]).to_not be_nil
          expect(output_building_5_data[:messages][:errors]).to be_nil.or be_empty
      end

      
      

    end
  end

  context 'Run and work with a small GEB simulation' do
    before :all do
      delete_directory_or_file(test_directory)
      system("#{call_cli} create --project-folder #{test_directory}")
      delete_directory_or_file(test_directory_res)
      system("#{call_cli} create --project-folder #{test_directory_res} --combined")
    end

    it 'runs a chilled water scenario with residential and commercial buildings', :GEB do
      # Use a ScenarioFile with only 2 buildings to reduce test time
      system("cp #{spec_dir / 'spec_files' / 'two_building_res_chilled_water_scenario.csv'} #{test_scenario_chilled}")
      # Include the chilled water mapper file
      system("cp #{example_dir / 'mappers' / 'ChilledWaterStorage.rb'} #{test_directory_res / 'mappers' / 'ChilledWaterStorage.rb'}")
      # modify the workflow file to include chilled water
      additional_measures = ['openstudio_results', 'add_chilled_water_storage_tank'] # 'BuildResidentialModel',
      select_measures(test_directory_res, additional_measures)
      # Run the residential project with the chilled water measure included in the workflow
      system("#{call_cli} run --scenario #{test_scenario_chilled} --feature #{test_feature_res}")
      # Turn off the measures activated specifically for this test
      select_measures(test_directory_res, additional_measures, skip_setting: true)
      expect((test_directory_res / 'run' / 'two_building_chilled' / '5' / 'finished.job').exist?).to be true
      expect((test_directory_res / 'run' / 'two_building_chilled' / '16' / 'finished.job').exist?).to be true
    end

    it 'runs a peak-hours MEL reduction scenario with residential and commercial buildings', :GEB do
      # Use a ScenarioFile with only 2 buildings to reduce test time
      system("cp #{spec_dir / 'spec_files' / 'two_building_res_peak_hours_mel_reduction.csv'} #{test_scenario_mels_reduction}")
      # Include the MEL reduction mapper file
      system("cp #{example_dir / 'mappers' / 'PeakHoursMelsShedding.rb'} #{test_directory_res / 'mappers' / 'PeakHoursMelsShedding.rb'}")
      # modify the workflow file to include MEL reduction
      additional_measures = ['openstudio_results', 'reduce_epd_by_percentage_for_peak_hours'] # 'BuildResidentialModel',
      select_measures(test_directory_res, additional_measures)
      # Run the residential project with the MEL reduction measure included in the workflow
      system("#{call_cli} run --scenario #{test_scenario_mels_reduction} --feature #{test_feature_res}")
      # Turn off the measures activated specifically for this test
      select_measures(test_directory_res, additional_measures, skip_setting: true)
      expect((test_directory_res / 'run' / 'two_building_mels_reduction' / '5' / 'finished.job').exist?).to be true
      expect((test_directory_res / 'run' / 'two_building_mels_reduction' / '16' / 'finished.job').exist?).to be true
    end

    it 'runs a peak-hours thermostat adjustment scenario with residential and commercial buildings', :GEB do
      # Use a ScenarioFile with only 2 buildings to reduce test time
      system("cp #{spec_dir / 'spec_files' / 'two_building_res_stat_adjustment.csv'} #{test_scenario_stat_adjustment}")
      # Include the thermostat adjustment mapper file
      system("cp #{example_dir / 'mappers' / 'PeakHoursThermostatAdjust.rb'} #{test_directory_res / 'mappers' / 'PeakHoursThermostatAdjust.rb'}")
      # modify the workflow file to include thermostat adjustment
      additional_measures = ['openstudio_results', 'AdjustThermostatSetpointsByDegreesForPeakHours'] # 'BuildResidentialModel',
      select_measures(test_directory_res, additional_measures)
      # Run the residential project with the thermostat adjustment measure included in the workflow
      system("#{call_cli} run --scenario #{test_scenario_stat_adjustment} --feature #{test_feature_res}")
      # Turn off the measures activated specifically for this test
      select_measures(test_directory_res, additional_measures, skip_setting: true)
      expect((test_directory_res / 'run' / 'two_building_stat_adjustment' / '5' / 'finished.job').exist?).to be true
      expect((test_directory_res / 'run' / 'two_building_stat_adjustment' / '16' / 'finished.job').exist?).to be true
    end

    it 'runs a flexible hot water scenario', :GEB do
      # https://github.com/NREL/openstudio-load-flexibility-measures-gem/tree/master/lib/measures/add_hpwh
      # Use a ScenarioFile with only 2 buildings to reduce test time
      system("cp #{spec_dir / 'spec_files' / 'two_building_flexible_hot_water.csv'} #{test_scenario_flexible_hot_water}")
      # Include the flexible hot water mapper file
      system("cp #{example_dir / 'mappers' / 'FlexibleHotWater.rb'} #{test_directory / 'mappers' / 'FlexibleHotWater.rb'}")
      # modify the workflow file to include flexible hot water
      additional_measures = ['openstudio_results', 'add_hpwh'] # 'BuildResidentialModel',
      select_measures(test_directory, additional_measures)
      # Run the residential project with the flexible hot water measure included in the workflow
      system("#{call_cli} run --scenario #{test_scenario_flexible_hot_water} --feature #{test_feature}")
      # Turn off the measures activated specifically for this test
      select_measures(test_directory, additional_measures, skip_setting: true)
      expect((test_directory / 'run' / 'two_building_flexible_hot_water' / '5' / 'finished.job').exist?).to be true
      expect((test_directory / 'run' / 'two_building_flexible_hot_water' / '2' / 'finished.job').exist?).to be true
    end

    it 'runs a ice-storage scenario', :GEB do
      # https://github.com/NREL/openstudio-load-flexibility-measures-gem/tree/master/lib/measures/add_central_ice_storage
      # Use a ScenarioFile with only 2 buildings to reduce test time
      system("cp #{spec_dir / 'spec_files' / 'two_building_thermal_storage_scenario.csv'} #{test_scenario_thermal_storage}")
      # Include the thermal storage mapper file
      system("cp #{example_dir / 'mappers' / 'ThermalStorage.rb'} #{test_directory / 'mappers' / 'ThermalStorage.rb'}")
      # modify the workflow file to include thermal storage
      additional_measures = ['openstudio_results', 'add_central_ice_storage']
      select_measures(test_directory, additional_measures)
      # Run the residential project with the thermal storage measures included in the workflow
      system("#{call_cli} run --scenario #{test_scenario_thermal_storage} --feature #{test_feature}")
      # Turn off the measures activated specifically for this test
      select_measures(test_directory, additional_measures, skip_setting: true)
      expect((test_directory / 'run' / 'two_building_thermal_storage' / '1' / 'finished.job').exist?).to be true
      expect((test_directory / 'run' / 'two_building_thermal_storage' / '12' / 'finished.job').exist?).to be true
    end
  end

  context 'Run and work with a small residential simulation' do
    before :all do
      delete_directory_or_file(test_directory_res)
      system("#{call_cli} create --project-folder #{test_directory_res} --combined")
      delete_directory_or_file(test_directory_res_hpxml)
      system("#{call_cli} create --project-folder #{test_directory_res_hpxml} --combined")
    end

    it 'runs a 2 building scenario with residential and commercial buildings', :residential do
      system("cp #{spec_dir / 'spec_files' / 'two_building_res.csv'} #{test_scenario_res}")
      system("#{call_cli} run --scenario #{test_scenario_res} --feature #{test_feature_res}")
      expect((test_directory_res / 'run' / 'two_building_res' / '5' / 'finished.job').exist?).to be true
      expect((test_directory_res / 'run' / 'two_building_res' / '16' / 'finished.job').exist?).to be true
    end

    it 'runs a 2 building residential scenario with an hpxml building', :residential do
      system("cp #{spec_dir / 'spec_files' / 'two_building_res_hpxml.csv'} #{test_scenario_res_hpxml}")
      system("#{call_cli} run --scenario #{test_scenario_res_hpxml} --feature #{test_feature_res}")
      expect((test_directory_res_hpxml / 'run' / 'two_building_res_hpxml' / '16' / 'finished.job').exist?).to be true
      expect((test_directory_res_hpxml / 'run' / 'two_building_res_hpxml' / '17' / 'finished.job').exist?).to be true
    end

    it 'returns graceful error message when non-US weather file is provided', :residential do
      skip('Skipping for GHA CI only. Error message is returned as expected but GHA runner does not see it.')
      csv_data = CSV.read(test_weather_file)
      original_wmo = csv_data[0][5] # first row, 5th column
      # Confirm we're using the correct piece of data
      expect(original_wmo).to eq '725280'
      # Re-write the weather file using a non-US WMO (Vancouver, BC)
      csv_data[0][5] = 718920
      CSV.open(test_weather_file, 'w') do |csv|
        csv_data.each do |row|
          csv << row
        end
      end

      # Attempt to run the residential project, expecting a graceful error message to be returned
      system("cp #{spec_dir / 'spec_files' / 'two_building_res.csv'} #{test_scenario_res}")

      stdout, stderr, status = Open3.capture3("#{call_cli} run --scenario #{test_scenario_res} --feature #{test_feature_res}")
      expect(stderr).to include('This is known to happen when your weather file is from somewhere outside of the United States.')

      csv_data = CSV.read(test_weather_file)
      # Put the original WMO back into the weather file
      csv_data[0][5] = original_wmo
      CSV.open(test_weather_file, 'w') do |csv|
        csv_data.each do |row|
          csv << row
        end
      end
      # Confirm we have restored the original WMO
      expect(CSV.open(test_weather_file, 'r', &:first)[5]).to eq(original_wmo)
    end

    it 'validates eui', :residential do
      # This test requires the 'runs a 2 building scenario with residential and commercial buildings' be run first
      test_validation_file = test_directory_res / 'validation_schema.yaml'
      expect { system("#{call_cli} validate --eui #{test_validation_file} --scenario #{test_scenario_res} --feature #{test_feature_res}") }
        .to output(a_string_including('is within bounds set by'))
        .to_stdout_from_any_process
      system("cp #{spec_dir / 'spec_files' / 'out_of_bounds_validation.yaml'} #{test_validate_bounds}")
      expect { system("#{call_cli} validate --eui #{test_validate_bounds} --scenario #{test_scenario_res} --feature #{test_feature_res}") }
        .to output(a_string_including('kBtu/ft2/yr is greater than the validation maximum'))
        .to_stdout_from_any_process
      expect { system("#{call_cli} validate --eui #{test_validate_bounds} --scenario #{test_scenario_res} --feature #{test_feature_res}") }
        .to output(a_string_including('is less than the validation minimum'))
        .to_stdout_from_any_process
      expect { system("#{call_cli} validate --eui #{test_validate_bounds} --scenario #{test_scenario_res} --feature #{test_feature_res} --units SI") }
        .to output(a_string_including('kWh/m2/yr is less than the validation minimum'))
        .to_stdout_from_any_process
    end
  end

  context 'Run and work with a small electric simulation' do
    before :all do
      delete_directory_or_file(test_directory_elec)
      # use this to test both opendss and disco workflows
      system("#{call_cli} create --project-folder #{test_directory_elec} --disco")
      delete_directory_or_file(test_directory_pv)
      system("#{call_cli} create --project-folder #{test_directory_pv} --photovoltaic")
    end

    it 'runs an electrical network scenario', :electric do
      system("cp #{spec_dir / 'spec_files' / 'electrical_scenario.csv'} #{test_scenario_elec}")
      system("#{call_cli} run --scenario #{test_scenario_elec} --feature #{test_feature_elec}")
      expect((test_directory_elec / 'run' / 'electrical_scenario' / '13' / 'finished.job').exist?).to be true
    end

    it 'runs a PV scenario when called with reopt', :electric do
      system("cp #{spec_dir / 'spec_files' / 'REopt_scenario.csv'} #{test_scenario_reopt}")
      # Copy in reopt folder
      system("cp -R #{spec_dir / 'spec_files' / 'reopt'} #{test_directory_pv / 'reopt'}")
      system("#{call_cli} run --scenario #{test_scenario_reopt} --feature #{test_feature_pv}")
      expect((test_directory_pv / 'reopt').exist?).to be true
      expect((test_directory_pv / 'reopt' / 'base_assumptions.json').exist?).to be true
      expect((test_directory_pv / 'run' / 'reopt_scenario' / '5' / 'finished.job').exist?).to be true
      expect((test_directory_pv / 'run' / 'reopt_scenario' / '2' / 'finished.job').exist?).to be true
      expect((test_directory_pv / 'run' / 'reopt_scenario' / '3' / 'finished.job').exist?).to be false
    end

    it 'successfully gets results from the opendss cli', :electric do
      # This test requires the 'runs an electrical network scenario' be run first
      system("#{call_cli} process --default --scenario #{test_scenario_elec} --feature #{test_feature_elec}")
      expect { system("#{call_cli} opendss --scenario #{test_scenario_elec} --feature #{test_feature_elec} --start-date 2017/01/15 --start-time 01:00:00 --end-date 2017/01/16 --end-time 00:00:00 --upgrade") }
        .to output(a_string_including('Upgrading undersized transformers:'))
        .to_stdout_from_any_process
      expect((test_directory_elec / 'run' / 'electrical_scenario' / 'opendss' / 'profiles' / 'load_1.csv').exist?).to be true
    end

    it 'successfully runs disco simulation', :electric do
      # This test requires the 'runs an electrical network scenario' be run first
      system("#{call_cli} disco --scenario #{test_scenario_elec} --feature #{test_feature_elec}")
      expect((test_directory_elec / 'run' / 'electrical_scenario' / 'disco').exist?).to be true
    end

    it 'reopt post-processes a scenario and visualize', :electric do
      # This test requires the 'runs a PV scenario when called with reopt' be run first
      system("#{call_cli} process --reopt-scenario --scenario #{test_scenario_reopt} --feature #{test_feature_pv}")
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'scenario_optimization.json').exist?).to be true
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'process_status.json').exist?).to be true
      # and visualize
      system("#{call_cli} visualize --feature #{test_feature_pv}")
      expect((test_directory_pv / 'run' / 'scenario_comparison.html').exist?).to be true
    end

    it 'reopt post-processes a scenario with specified scenario assumptions file', :electric do
      # This test requires the 'runs a PV scenario when called with reopt' be run first
      expect { system("#{call_cli} process --reopt-scenario -a #{test_reopt_scenario_assumptions_file} --scenario #{test_scenario_reopt} --feature #{test_feature_pv}") }
        .to output(a_string_including('multiPV_assumptions.json'))
        .to_stdout_from_any_process
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'scenario_optimization.json').exist?).to be true
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'process_status.json').exist?).to be true
    end

    it 'reopt post-processes a scenario with resilience reporting', :electric do
      skip('Resilience processing is not yet implemented with REopt v3')
      # This test requires the 'runs a PV scenario when called with reopt' be run first
      system("#{call_cli} process --reopt-scenario --reopt-resilience --scenario #{test_scenario_reopt} --feature #{test_feature_pv}")
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'scenario_optimization.json').exist?).to be true
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'process_status.json').exist?).to be true
      # path_to_resilience_report_file = test_directory_pv / 'run' / 'reopt_scenario' / 'reopt' / 'scenario_report_reopt_scenario_reopt_run_resilience.json'
    end

    it 'reopt post-processes each feature and visualize', :electric do
      # This test requires the 'runs a PV scenario when called with reopt' be run first
      system("#{call_cli} process --reopt-feature --scenario #{test_scenario_reopt} --feature #{test_feature_pv}")
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'feature_optimization.csv').exist?).to be true
      # and visualize
      system("#{call_cli} visualize --scenario #{test_scenario_reopt}")
      expect((test_directory_pv / 'run' / 'reopt_scenario' / 'feature_comparison.html').exist?).to be true
    end

    it 'opendss post-processes a scenario', :electric do
      # This test requires the 'successfully gets results from the opendss cli' be run first
      expect((test_directory_elec / 'run' / 'electrical_scenario' / '2' / 'feature_reports' / 'default_feature_report_opendss.csv').exist?).to be false
      system("#{call_cli} process --opendss --scenario #{test_scenario_elec} --feature #{test_feature_elec}")
      expect((test_directory_elec / 'run' / 'electrical_scenario' / '2' / 'feature_reports' / 'default_feature_report_opendss.csv').exist?).to be true
      expect((test_directory_elec / 'run' / 'electrical_scenario' / 'process_status.json').exist?).to be true
    end
  end
end
