// Lightweight program to take the sensor data from a Voltronic Axpert, Mppsolar PIP, Voltacon, Effekta, and other branded OEM Inverters and send it to a MQTT server for ingestion...
// Adapted from "Maio's" C application here: https://skyboo.net/2017/03/monitoring-voltronic-power-axpert-mex-inverter-under-linux/
//
// Please feel free to adapt this code and add more parameters -- See the following forum for a breakdown on the RS323 protocol: http://forums.aeva.asn.au/viewtopic.php?t=4332
// ------------------------------------------------------------------------

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

#include "main.h"
#include "tools.h"
#include "inputparser.h"

#include <pthread.h>
#include <signal.h>
#include <string.h>

#include <thread>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <fstream>


bool debugFlag = false;
bool runOnce = false;

cInverter *ups = NULL;

// ---------------------------------------
// Global configs read from 'inverter.conf'

string devicename;
vector<std::string> commands;
float ampfactor;
float wattfactor;

// ---------------------------------------

// trim from start (in place)
static inline void ltrim(std::string &s) {
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), [](unsigned char ch) {
        return !std::isspace(ch);
    }));
}

// trim from end (in place)
static inline void rtrim(std::string &s) {
    s.erase(std::find_if(s.rbegin(), s.rend(), [](unsigned char ch) {
        return !std::isspace(ch);
    }).base(), s.end());
}

// trim from both ends (in place)
static inline void trim(std::string &s) {
    ltrim(s);
    rtrim(s);
}

void attemptSplitString(vector<std::string>& addTo, std::string addFrom) {
    addTo.clear();

    string delimiter = ",";
    addFrom += delimiter;

    size_t pos = 0;
    string token;

    while ((pos = addFrom.find(delimiter)) != std::string::npos) {
        token = addFrom.substr(0, pos);
        trim(token);
        if (token.length() > 0) {
            addTo.push_back(token);
        }
        addFrom.erase(0, pos + delimiter.length());
    }
}

void attemptAddSetting(int *addTo, string addFrom) {
    try {
        *addTo = stof(addFrom);
    } catch (exception e) {
        cout << e.what() << '\n';
        cout << "There's probably a string in the settings file where an int should be.\n";
    }
}

void attemptAddSetting(float *addTo, string addFrom) {
    try {
        *addTo = stof(addFrom);
    } catch (exception e) {
        cout << e.what() << '\n';
        cout << "There's probably a string in the settings file where a floating point should be.\n";
    }
}

void getSettingsFile(string filename) {
    if (debugFlag) {
      printf("INVERTER: Getting settings\n");
    }
    try {
        string fileline, linepart1, linepart2;
        ifstream infile;
        infile.open(filename);

        while(!infile.eof()) {
            getline(infile, fileline);
            size_t firstpos = fileline.find("#");

            if(firstpos != 0 && fileline.length() != 0) {    // Ignore lines starting with # (comment lines)
                size_t delimiter = fileline.find("=");
                linepart1 = fileline.substr(0, delimiter);
                linepart2 = fileline.substr(delimiter+1, string::npos - delimiter);

                if(linepart1 == "device")
                    devicename = linepart2;
                else if(linepart1 == "commands")
                    attemptSplitString(commands, linepart2);
                else if(linepart1 == "amperage_factor")
                    attemptAddSetting(&ampfactor, linepart2);
                else if(linepart1 == "watt_factor")
                    attemptAddSetting(&wattfactor, linepart2);
                else
                    continue;
            }
        }
        infile.close();
    } catch (...) {
        cout << "Settings could not be read properly...\n";
    }
}

// ==============

void printJsonOutput(string *rawOutput, const char *cmd) {

    // Reply1 - QPIGS
    float voltage_grid;
    float freq_grid;
    float voltage_out;
    float freq_out;
    int load_va;
    int load_watt;
    int load_percent;
    int voltage_bus;
    float voltage_batt;
    int batt_charge_current;
    int batt_capacity;
    int temp_heatsink;
    float pv_input_current;
    float pv_input_voltage;
    float pv_input_watts;
    float pv_input_watthour;
    float load_watthour = 0;
    float scc_voltage;
    int batt_discharge_current;
    char device_status[8];
    float pv_charging_power;
    int fan_voltage_offset;
    int eeprom_version;
    char device_status_2[3];

    // Reply2 - QPIRI
    float grid_voltage_rating;
    float grid_current_rating;
    float out_voltage_rating;
    float out_freq_rating;
    float out_current_rating;
    int out_va_rating;
    int out_watt_rating;
    float batt_rating;
    float batt_recharge_voltage;
    float batt_under_voltage;
    float batt_bulk_voltage;
    float batt_float_voltage;
    int batt_type;
    int max_grid_charge_current;
    int max_charge_current;
    int in_voltage_range;
    int out_source_priority;
    int charger_source_priority;
    int parallel_max_num;
    int machine_type;
    int topology;
    int out_mode;
    float batt_redischarge_voltage;

    printf("{");
    printf("\"type\":\"%s\",", cmd);
    printf("\"raw\":\"%s\"", rawOutput->c_str());

    if (strcmp(cmd, "QMOD") == 0) {

        int mode = 0;
        mode = ups->GetMode(rawOutput->c_str()[0]);
        printf(",");
        printf("\"Inverter_mode\":%d", mode);

    } else if (strcmp(cmd, "QPIGS") == 0) {

        sscanf(rawOutput->c_str(), "%f %f %f %f %d %d %d %d %f %d %d %d %f %f %f %d %s %d %d %f %s", &voltage_grid, &freq_grid, &voltage_out, &freq_out, &load_va, &load_watt, &load_percent,
            &voltage_bus, &voltage_batt, &batt_charge_current, &batt_capacity, &temp_heatsink, &pv_input_current, &pv_input_voltage, &scc_voltage, &batt_discharge_current,
            (char *)&device_status, &fan_voltage_offset, &eeprom_version, &pv_charging_power, (char *)&device_status_2);

        // There appears to be a discrepancy in actual DMM measured current vs what the meter is
        // telling me it's getting, so lets add a variable we can multiply/divide by to adjust if
        // needed.  This should be set in the config so it can be changed without program recompile.

        pv_input_current = pv_input_current * ampfactor;

        // It appears on further inspection of the documentation, that the input current is actually
        // current that is going out to the battery at battery voltage (NOT at PV voltage).  This
        // would explain the larger discrepancy we saw before.

        pv_input_watts = (scc_voltage * pv_input_current) * wattfactor;

        // Calculate watt-hours generated per run interval period (given as program argument)
        pv_input_watthour = pv_input_watts / (3600 / 360);
        load_watthour = (float)load_watt / (3600 / 360);

        printf(",");
        printf("\"AC_grid_voltage\":%.1f,", voltage_grid);
        printf("\"AC_grid_frequency\":%.1f,", freq_grid);
        printf("\"AC_out_voltage\":%.1f,", voltage_out);
        printf("\"AC_out_frequency\":%.1f,", freq_out);
        printf("\"PV_in_voltage\":%.2f,", pv_input_voltage);
        printf("\"PV_in_current\":%.2f,", pv_input_current);
        printf("\"PV_in_watts\":%.2f,", pv_input_watts);
        printf("\"PV_charging_power\":%.1f,", pv_charging_power);
        printf("\"PV_in_watthour\":%.4f,", pv_input_watthour);
        printf("\"SCC_voltage\":%.4f,", scc_voltage);
        printf("\"Load_pct\":%d,", load_percent);
        printf("\"Load_watt\":%d,", load_watt);
        printf("\"Load_watthour\":%.4f,", load_watthour);
        printf("\"Load_va\":%d,", load_va);
        printf("\"Bus_voltage\":%d,", voltage_bus);
        printf("\"Heatsink_temperature\":%d,", temp_heatsink);
        printf("\"Battery_capacity\":%d,", batt_capacity);
        printf("\"Battery_voltage\":%.2f,", voltage_batt);
        printf("\"Battery_charge_current\":%d,", batt_charge_current);
        printf("\"Battery_discharge_current\":%d,", batt_discharge_current);
        printf("\"Load_status_on\":%c,", device_status[3]);
        printf("\"SCC_charge_on\":%c,", device_status[6]);
        printf("\"AC_charge_on\":%c,", device_status[7]);
        printf("\"Floating_mode\":%c,", device_status_2[0]);
        printf("\"Switch_on\":%c,", device_status_2[1]);
        printf("\"Reserved_flag\":%c,", device_status_2[2]);
        printf("\"Fan_voltage_offset\":%d,", fan_voltage_offset);
        printf("\"EEPROM_version\":%d", eeprom_version);

    } else if (strcmp(cmd, "QPIRI") == 0) {

        sscanf(rawOutput->c_str(), "%f %f %f %f %f %d %d %f %f %f %f %f %d %d %d %d %d %d %d %d %d %d %f",
            &grid_voltage_rating, &grid_current_rating, &out_voltage_rating, &out_freq_rating, &out_current_rating, &out_va_rating, &out_watt_rating,
            &batt_rating, &batt_recharge_voltage, &batt_under_voltage, &batt_bulk_voltage, &batt_float_voltage, &batt_type, &max_grid_charge_current,
            &max_charge_current, &in_voltage_range, &out_source_priority, &charger_source_priority, &parallel_max_num, &machine_type, &topology,
            &out_mode, &batt_redischarge_voltage);

        printf(",");
        printf("\"Battery_recharge_voltage\":%.1f,", batt_recharge_voltage);
        printf("\"Battery_under_voltage\":%.1f,", batt_under_voltage);
        printf("\"Battery_bulk_voltage\":%.1f,", batt_bulk_voltage);
        printf("\"Battery_float_voltage\":%.1f,", batt_float_voltage);
        printf("\"Max_grid_charge_current\":%d,", max_grid_charge_current);
        printf("\"Parallel_max_num\":%d,", parallel_max_num);
        printf("\"Max_charge_current\":%d,", max_charge_current);
        printf("\"Out_source_priority\":%d,", out_source_priority);
        printf("\"Charger_source_priority\":%d,", charger_source_priority);
        printf("\"Battery_redischarge_voltage\":%.1f", batt_redischarge_voltage);

    }

    printf("}\n");
    fflush(stdout);
}

// ==============

int main(int argc, char* argv[]) {

    // Get command flag settings from the arguments (if any)
    InputParser cmdArgs(argc, argv);

    const string &rawcmd = cmdArgs.getCmdOption("-r");

    const string &rawcmds = cmdArgs.getCmdOption("-c");
    const string &rawcmds2 = cmdArgs.getCmdOption("--commands");

    if(cmdArgs.cmdOptionExists("-h") || cmdArgs.cmdOptionExists("--help")) {
        return print_help();
    }
    if(cmdArgs.cmdOptionExists("-d")) {
        debugFlag = true;
    }
    if(cmdArgs.cmdOptionExists("-1") || cmdArgs.cmdOptionExists("--run-once")) {
        runOnce = true;
    }
    lprintf("INVERTER: Debug set");

    // Get the rest of the settings from the conf file
    if( access( "./inverter.conf", F_OK ) != -1 ) { // file exists
        getSettingsFile("./inverter.conf");
    } else { // file doesn't exist
        getSettingsFile("/etc/inverter/inverter.conf");
    }

    ups = new cInverter(devicename);

    if (!rawcmd.empty()) {
        commands = vector<string>{ rawcmd };
    } else {
        if (!rawcmds.empty()) {
            attemptSplitString(commands, rawcmds);
        } else if (!rawcmds2.empty()) {
            attemptSplitString(commands, rawcmds2);
        }
        if (debugFlag) {
            printf("INVERTER: Running the following commands: ");
            for (int i = 0; i < commands.size(); i++) {
                printf("%s ", commands[i].data());
            }
            printf("\n");
        }
    }

    while (true) {
      for (int i = 0; i < commands.size(); i++) {

        ups->ExecuteCmd(commands[i]);
        string *rawOutput = ups->GetReply();
        if (rawOutput) {
          printJsonOutput(rawOutput, commands[i].data());
          delete rawOutput;
        }

        sleep(0.1);
      }

      if(runOnce) {
          // Do once and exit instead of loop endlessly
          exit(0);
      }

      sleep(0.3);
    }

    if (ups) {
        delete ups;
    }
    return 0;
}
