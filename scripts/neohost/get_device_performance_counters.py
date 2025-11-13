#!/usr/bin/env python

# --
#                 - Mellanox Confidential and Proprietary -
#
# Copyright (C) Jan 2013, Mellanox Technologies Ltd.  ALL RIGHTS RESERVED.
#
# Except as specifically permitted herein, no portion of the information,
# including but not limited to object code and source code, may be reproduced,
# modified, distributed, republished or otherwise exploited in any form or by
# any means for any purpose without the prior written permission of Mellanox
# Technologies Ltd. Use of software subject to the terms and conditions
# detailed in the file "LICENSE.txt".
# --

# @author: Simon Raviv
# @date: August 28, 2017


import os
import sys
import time
import json
import datetime
import optparse
import re
import collections

from itertools import izip_longest

import neohost_sdk_constants as NC
from command_sdk import CommandSdk
from neohost_sdk_exception import NeohostSdkException


SUPER_OPTION = ['--mode', '--dev-uid', '--DEBUG', '--port']


class Colors(object):
    """ Represents Linux shell colors.
    """
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'


class Keys(object):
    """ Describes a key in the API schema.
    """

    COUNTER = "counter"
    COUNTERS = "counters"
    PERFORMANCE_COUNTERS = "performanceCounters"
    METADATA = "metadata"
    METADATAGROUP = "metadataGroup"
    SYS_STAT = "GetSystemStaticPerformanceConfig"
    DEVICE_COUNTERS = "GetDevicePerformanceCounters"
    GROUPS = "groups"
    GROUP = "group"
    ANALYSIS = "analysis"
    ANALYSIS_ATTRIBUTE = "analysisAttribute"
    ANALYSIS_ATTRIBUTES = "analysisAttributes"
    ANALYSIS_METADATAGROUP = "analysisMetadataGroup"
    ANALYSIS_METADATA = "analysisMetadata"
    NAME = "name"
    NAMES = "names"
    DESCRIPTION = "description"
    UNITS = "units"
    UNIT = "unit"
    TIMESTAMP = "timestamp"
    VALUE = "value"
    VALUE_TYPE = "valueType"
    UTILIZATION_PERCENT = "utilizationPercentage"
    UTILIZATION_REF = "utilizationReference"
    GOOD_THRESHOLD = "thresholdGood"
    BAD_THRESHOLD = "thresholdBad"
    GUI_CMPONENT = "GUIComponent"
    ANALYZERS = "analyzers"


class Utils(object):
    """ Utilities class for the command.
    """

    @staticmethod
    def formatNumber(number):
        """ Convert a number to comma separated number.
        """
        result = []

        if isinstance(number, float):
            result = str(number)
        if isinstance(number, (int, long)):
            for index, char in enumerate(reversed(str(number))):
                if index and (not (index % 3)):
                    result.insert(0, ',')
                result.insert(0, char)
            result = ''.join(result)
        return result

class GetDevicePerformanceCounters(CommandSdk):
    """ Handle performance counters from the device.
    """

    def __init__(self):
        super(GetDevicePerformanceCounters, self).__init__()
        self.__showDescription = None
        self.__showUnitCounters = None
        self.__runLoop = None
        self.__recordPath = None
        self.__replayPath = None
        self.__namesMax = None
        self.__descriptionsMax = None
        self.__analysisMax = None
        self.__delay = None
        self.__getAnalysis = None
        self._outputFormatDefault = NC.OutputFormatOptions.READABLE
        self._outputFormatOptions.append(NC.OutputFormatOptions.READABLE)

    def addOptions(self):
        super(GetDevicePerformanceCounters, self).addOptions()
        self._cmdParser.add_option("--dev-uid", dest="devUid",
                                   help=NC.
                                   HELP_DEV_UID,
                                   default=None)
        self._cmdParser.add_option("--show-description",
                                   dest="showDescription",
                                   help=NC.
                                   HELP_DESCRIPTION_PERFORMANCE_COUNTERS,
                                   action="store_true",
                                   default=False)
        self._cmdParser.add_option("--show-unit-counters",
                                   dest="showUnitCounters",
                                   help=NC.
                                   HELP_UNITS_PERFORMANCE_COUNTERS,
                                   action="store_true",
                                   default=False)
        self._cmdParser.add_option("--run-loop", dest="runLoop",
                                   help=NC.
                                   HELP_COUNTINUES_RUN_PERFORMANCE_COUNTERS,
                                   action="store_true",
                                   default=False)
        self._cmdParser.add_option("--record-path", dest="recordPath",
                                   help=NC.
                                   HELP_RECORD_RUN_PERFORMANCE_COUNTERS,
                                   action="store",
                                   metavar="FULL_FILE_PATH",
                                   default=False)
        self._cmdParser.add_option("--replay-path", dest="replayPath",
                                   help=NC.
                                   HELP_REPLAY_RUN_PERFORMANCE_COUNTERS,
                                   action="store",
                                   metavar="FULL_FILE_PATH",
                                   default=False)
        self._cmdParser.add_option("--delay", dest="delay",
                                   help=NC.
                                   HELP_DELAY_RUN_PERFORMANCE_COUNTERS,
                                   action="store",
                                   metavar="DELAY_SECONDS")
        self._cmdParser.add_option("--get-analysis", dest="getAnalysis",
                                   help=NC.
                                   HELP_GET_ANALYSIS,
                                   action="store_true",
                                   default=True)
        examples = NC.PERFORMANCE_USAGE_EXAMPLES
        examplesGroup = optparse.OptionGroup(
            self._cmdParser, "Examples", examples)
        self._cmdParser.add_option_group(examplesGroup)

        # Override parser defaults:
        self._cmdParser.set_defaults(runMode=NC.SHELL_MODE)

    def parseOptions(self):
        # Deleted unsupported option:
        self._cmdParser.remove_option('--exec-mode')
        # Ovveride base default format option:
        self._cmdParser.set_defaults(
            outputFormat=NC.OutputFormatOptions.READABLE)

        super(GetDevicePerformanceCounters, self).parseOptions()
        self._returnRespond = True
        self.__devUid = self._options.devUid
        self._outputFormat = self._options.outputFormat
        self.__showDescription = self._options.showDescription
        self.__showUnitCounters = self._options.showUnitCounters
        self.__runLoop = self._options.runLoop
        self.__recordPath = self._options.recordPath
        self.__replayPath = self._options.replayPath
        self.__delay = self._options.delay if self._options.delay else 1
        self.__getAnalysis = self._options.getAnalysis
        self._outputFormat = NC.OutputFormatOptions.READABLE
        if self._options.outputFormat:
            self._outputFormat = self._options.outputFormat

    def prepareRequest(self):
        super(GetDevicePerformanceCounters, self).prepareRequest()
        requsetParameters = dict()
        requsetParameters[NC.PARAM_DEV_UID] = self.__devUid
        if self.__recordPath:
            requsetParameters[NC.PARAM_RECORD_PATH] = self.__recordPath
        if self.__getAnalysis:
            requsetParameters[NC.PARAM_GET_ANALYSIS] = self.__getAnalysis
        self.request[NC.ATTR_METHOD] = \
            NC.METHOD_GET_DEVICE_PERFORMANCE_COUNTERS
        self.request[NC.ATTR_MODULE] = NC.MODULE_PERFORMANCE
        self.request[NC.ATTR_PARAMS] = requsetParameters

    def __validateSingleOption(self, option, pass_list, parameters,
                               optionParameter=None):
        """ Validates single option from argument list.
        """
        for param in parameters:
            if param != option and param not in pass_list:
                if optionParameter is not None:
                    option = "{option}={value}".format(option=option,
                                                       value=optionParameter)
                raise NeohostSdkException(NC.PARAMETERS_CHOOSE_AVAILABLE %
                                          (option, pass_list))

    def validateOptions(self):
        if not self.__replayPath:
            super(GetDevicePerformanceCounters, self).validateOptions()

        destList = list()
        parameters = list()
        allParameters = list()
        for dest, value in vars(self._options).items():
            if value:
                destList.append(dest)
        for option in self._cmdParser.option_list:
            if option.dest in destList:
                if option.get_opt_string() not in SUPER_OPTION:
                    parameters.append(option.get_opt_string())
                allParameters.append(option.get_opt_string())

        # Validate that valid option has been chosen:
        if not parameters:
            raise NeohostSdkException(NC.MISSING_CHOSEN_OPTION)

        # Validate --dev-uid option:
        if not self.__replayPath:
            if (self.__showUnitCounters or self.__recordPath
               or self._outputFormat) and not self.__devUid:
                raise NeohostSdkException("%s" % NC.MISSING_DEV_UID)

        # Validate --output-format=JSON:
        if self._outputFormat == NC.OutputFormatOptions.JSON:
            pass_list = ['--get-analysis'] + SUPER_OPTION
            self.__validateSingleOption('--output-format',
                                        pass_list,
                                        parameters,
                                        NC.OutputFormatOptions.JSON)

        # Validate --replay-path and delay options:
        if self.__replayPath:
            pass_list = ['--delay', '--show-description', '--get-analysis',
                         '--output-format']
            self.__validateSingleOption('--replay-path',
                                        pass_list,
                                        parameters)

        # Validate --show-unit-counters option:
        if self.__showUnitCounters:
            pass_list = (['--output-format', '--get-analysis']
                        + SUPER_OPTION)
            self.__validateSingleOption('--show-unit-counters',
                                        pass_list,
                                        parameters)

        # Validate --record-path option:
        if self.__recordPath:
            pass_list = (['--show-description', '--get-analysis',
                          '--output-format'] + SUPER_OPTION)
            self.__validateSingleOption('--record-path',
                                        pass_list,
                                        parameters)

        # Validate --output-format=readable:
        if self._outputFormat == NC.OutputFormatOptions.READABLE:
            pass_list = (['--show-description', '--run-loop',
                          '--get-analysis', '--show-unit-counters',
                          '--record-path', '--replay-path', '--delay']
                         + SUPER_OPTION)
            self.__validateSingleOption('--output-format',
                                        pass_list,
                                        parameters,
                                        NC.OutputFormatOptions.READABLE)

        # Validate --show-description option:
        if self.__showDescription:
            pass_list = (['--output-format', '--run-loop', '--get-analysis',
                          '--replay-path', '--record-path', '--delay']
                         + SUPER_OPTION)
            self.__validateSingleOption('--show-description',
                                        pass_list,
                                        parameters)

        # Validate --run-loop option:
        if self.__runLoop:
            pass_list = (['--output-format',
                          '--show-description', '--get-analysis']
                         + SUPER_OPTION)
            self.__validateSingleOption('--run-loop',
                                        pass_list,
                                        parameters)

    def __runCommand(self):
        self.postRequest()
        jsonResponse = self.getResponse()
        response = json.loads(jsonResponse)
        if "error" in response:
            message = "-E- {error}".format(error=response["error"]["message"])
            print message
            return NC.RC_FAIL, None
        else:
            response = response["result"]["performanceCounters"]
            return NC.RC_SUCCESS, response

    def runCommand(self):
        self.addOptions()
        self.parseOptions()
        self.validateOptions()

        if self.__replayPath:
            rc = self.__replay()
            return rc

        self.prepareRequest()
        rc, response = self.__runCommand()

        if rc == NC.RC_FAIL:
            return rc
        elif self._outputFormat == NC.OutputFormatOptions.JSON:
            print json.dumps(response)
        elif self.__recordPath:
            rc = self.__record(response)
        elif self.__showUnitCounters:
            rc = self.__printUnitsCounters(response)
        elif self._outputFormat == NC.OutputFormatOptions.READABLE:
            if self.__runLoop:
                rc = self.__continuesPrint(response)
            else:
                rc = self.__printNice(response)
        else:
            print "-E- Please choose option(s) from the help screen"
            rc = NC.RC_FAIL
        return rc

    def __printUnitsCounters(self, response):
        """ Prints the counters in each unit.
        """
        groups = response[Keys.METADATA][Keys.GROUPS]
        names = list()

        for counter in response[Keys.COUNTERS]:
            names.append(len(counter[Keys.COUNTER][Keys.NAME]))

        namesMax = max(names)
        tableSeparatorLen = namesMax + 6
        tableSeparator = ("{0:=^%s}" % tableSeparatorLen).format('')
        unitFormat = "||{start_color}{unit:^{space}}{end_color}||"
        coutnerFormat = "|| {counter:<{space}} ||"

        for group in groups:
            group = group[Keys.METADATAGROUP]
            unit = group[Keys.UNIT]
            unit = unit[unit.index('(') + 1: unit.index(')')]
            counters = group[Keys.COUNTERS]
            if not (len(counters) and unit):
                continue
            print tableSeparator
            print unitFormat.format(start_color=Colors.HEADER + Colors.BOLD,
                                    unit=unit,
                                    space=namesMax + 2,
                                    end_color=Colors.ENDC)
            print tableSeparator
            for counter in counters:
                print coutnerFormat.format(counter=counter,
                                           space=namesMax)
        print tableSeparator
        return NC.RC_SUCCESS

    def __buildOut(self, output, current):
        """ Build output list.
        """
        output.append(current)

    def __buildCountersResult(self, response):
        """ Build counters result output list.
        """
        output = list()

        # Calculate max name and description length ones:
        if not (self.__namesMax and self.__descriptionsMax):
            names = list()
            descriptions = list()
            for counter in response[Keys.COUNTERS]:
                names.append(len(counter[Keys.COUNTER][Keys.NAME]))
                descriptions.append(
                    len(counter[Keys.COUNTER][Keys.DESCRIPTION]))
            self.__namesMax = max(names)
            self.__descriptionsMax = max(descriptions)

        # Build table formating variables:
        headerField = Colors.HEADER + Colors.BOLD + "{field}" + Colors.ENDC
        headline = [headerField.format(field="Counter Name"),
                    headerField.format(field="Counter Value")]
        headlineFormat = "|| {0:<%s} || {1:<29}||" % (self.__namesMax + 13)
        tableSeparatorLen = self.__namesMax + 25

        if self.__showDescription:
            headline.append(headerField.format(field=Keys.DESCRIPTION))
            headlineFormat += " {2:<%s}||" % (self.__descriptionsMax + 14)
            tableSeparatorLen += self.__descriptionsMax + 4

        tableSeparator = "{0:={align}{width}}".format(
            '', width=tableSeparatorLen, align='^')

        self.__buildOut(output, tableSeparator)
        self.__buildOut(output, headlineFormat.format(*headline))
        self.__buildOut(output, tableSeparator)

        for counter in response[Keys.COUNTERS]:
            counter = counter[Keys.COUNTER]
            name = counter[Keys.NAME]
            value = Utils.formatNumber(counter[Keys.VALUE])
            description = counter[Keys.DESCRIPTION]
            utilization = counter[Keys.UTILIZATION_PERCENT]
            goodThreshold = counter[Keys.GOOD_THRESHOLD]
            badThreshold = counter[Keys.BAD_THRESHOLD]
            rowFormat = ("|| {startColor}{name:<%s}{endColor} ||"
                         " {startColor}{value:<16}{endColor}||" %
                         self.__namesMax)
            color = ''

            if goodThreshold == "N/A" or badThreshold == "N/A":
                color = ''
            elif utilization <= goodThreshold:
                color = Colors.OKGREEN
            elif goodThreshold < utilization < badThreshold:
                color = Colors.WARNING
            elif utilization >= badThreshold:
                color = Colors.FAIL
            if self.__showDescription:
                rowFormat += (" {startColor}{description:<%s}{endColor} ||" %
                              self.__descriptionsMax)
            else:
                description = ''

            row = rowFormat.format(name=name,
                                   value=value,
                                   description=description,
                                   startColor=color,
                                   endColor=Colors.ENDC)
            self.__buildOut(output, row)
        self.__buildOut(output, tableSeparator)
        return NC.RC_SUCCESS, output

    def __buildAnalysisResult(self, response):
        """ Build analysis result output list.
        """
        output = list()

        if not self.__getAnalysis or self.__showDescription \
            or Keys.ANALYSIS not in response:
                return NC.RC_SUCCESS, ''

        # Build analyzer by group structure:
        groups = dict()
        for group in response[Keys.ANALYSIS_METADATA][Keys.GROUPS]:
            group = group[Keys.ANALYSIS_METADATAGROUP]
            if group[Keys.ANALYSIS_ATTRIBUTES]:
                groups[group[Keys.GROUP]] = {
                    Keys.NAMES: group[Keys.ANALYSIS_ATTRIBUTES],
                    Keys.ANALYZERS: list()
                }
        groups = collections.OrderedDict(sorted(groups.items()))

        for analyzer in response[Keys.ANALYSIS]:
            analyzer = analyzer[Keys.ANALYSIS_ATTRIBUTE]
            for group_name, group in groups.iteritems():
                if analyzer[Keys.NAME] in group[Keys.NAMES]:
                    group[Keys.ANALYZERS].append(analyzer)

        # Sort analyzers in groups:
        for group_name, group in groups.iteritems():
            group[Keys.ANALYZERS] = sorted(
                group[Keys.ANALYZERS], key=lambda item: item['name'])

        # Calculate max name length ones:
        if not self.__analysisMax:
            analyzers = list()
            for analyzer in response[Keys.ANALYSIS]:
                analyzers.append(
                    len(analyzer[Keys.ANALYSIS_ATTRIBUTE][Keys.NAME]))
            self.__analysisMax = max(analyzers)

        # Build table formating variables:
        headerField = Colors.HEADER + Colors.BOLD + "{field}" + Colors.ENDC
        headline = [headerField.format(field="Performance Analysis"),
                    headerField.format(field="Analysis Value [Units]")]
        headerField = Colors.OKBLUE + "{field}" + Colors.ENDC
        headlineFormat = "| {0:{align}{width}} || {1:<45} ||"
        tableSeparatorLen = self.__analysisMax + 40
        tableSeparator = "{0:={align}{width}}".format(
            '', width=tableSeparatorLen, align='^')

        self.__buildOut(output, tableSeparator)
        self.__buildOut(output,
                        headlineFormat.format(*headline,
                                              width=(self.__analysisMax + 13),
                                              align='<'))
        self.__buildOut(output, tableSeparator)

        # Build analyzers results:
        for groupName, group in groups.iteritems():
            groupNameFormat = "|{name:^%s}||" % (tableSeparatorLen + 7)
            groupName = groupNameFormat.format(
                name=headerField.format(field=groupName))
            self.__buildOut(output, groupName)
            self.__buildOut(output, '-' * tableSeparatorLen)
            for analyzer in group[Keys.ANALYZERS]:
                name = analyzer[Keys.NAME]
                value = analyzer[Keys.VALUE]
                value = Utils.formatNumber(
                    int(value) if int(value) == value else round(value, 4))
                description = analyzer[Keys.DESCRIPTION]
                units = "[{0}]".format(analyzer[Keys.UNITS])

                rowFormat = \
                    "| {name:{align}{width}} || {value:<13} {units:<18} ||"
                row = rowFormat.format(name=name, value=value, units=units,
                                       width=self.__analysisMax, align='<')

                self.__buildOut(output, row)
            self.__buildOut(output, tableSeparator)
        return NC.RC_SUCCESS, output

    def __printNice(self, response):
        """ Prints the JSON response in readable manner.
        """
        returnValue = NC.RC_FAIL
        ret, countersOutput = self.__buildCountersResult(response)
        returnValue = returnValue or ret
        ret, analysisOutput = self.__buildAnalysisResult(response)
        returnValue = returnValue or ret

        table = izip_longest(countersOutput, analysisOutput, fillvalue='')
        for counter, analyzer in table:
            print "{0}{1}".format(counter, analyzer)

        return returnValue

    def __continuesPrint(self, response):
        """ Print the counters until kill signal occurred.
        """
        try:
            os.system('clear')
            rc = NC.RC_SUCCESS
            while True:
                self.__printNice(response)
                rc, response = self.__runCommand()
                if rc == NC.RC_FAIL:
                    return rc
                os.system('clear')
        except KeyboardInterrupt:
            print " pressed, exiting..."
            self.getResponse()
            return rc

    def __record(self, response):
        """ Record the session until kill signal occurred.
        """
        try:
            rc = NC.RC_SUCCESS
            objects = 1
            separator = "{0:=^62}".format('')
            while True:
                os.system("clear")
                self.__printNice(response)
                first_counter = response[Keys.COUNTERS][0][Keys.COUNTER]
                timeStamp = first_counter[Keys.TIMESTAMP] / 1000
                timeStamp = datetime.datetime.fromtimestamp(
                    timeStamp).strftime('%Y-%m-%d %H:%M:%S')
                print ("|| Recording in progress,"
                       " press Ctrl+c to stop recording... ||")
                print separator
                print ("|| Record Time Stamp |"
                       " {time:<36} ||").format(time=timeStamp)
                print separator
                print ("|| Number of objects |"
                       " {objects:<36} ||").format(objects=objects)
                print separator
                objects += 1
                rc, response = self.__runCommand()
                if rc == NC.RC_FAIL:
                    return rc
        except KeyboardInterrupt:
            print " pressed, the log is in {path}, exiting...".format(
                path=self.__recordPath)
            self.getResponse()
            return rc

    def __replay(self):
        """ Replay recorded live session.
        """
        try:
            rc = NC.RC_SUCCESS
            separator = "{0:=^49}".format('')
            log = open(self.__replayPath, 'r')
            for record in log:
                os.system("clear")
                record = json.loads(record)
                record = record["performanceCounters"]
                first_counter = record[Keys.COUNTERS][0][Keys.COUNTER]
                timeStamp = first_counter[Keys.TIMESTAMP] / 1000
                timeStamp = datetime.datetime.fromtimestamp(
                    timeStamp).strftime('%Y-%m-%d %H:%M:%S')
                self.__printNice(record)
                print "|| Replay in progress, press Ctrl+c to stop... ||"
                print separator
                print "|| Time Stamp | {timestamp:<30} ||" \
                    .format(timestamp=timeStamp)
                print separator
                time.sleep(int(self.__delay))
                if rc == NC.RC_FAIL:
                    return rc
        except KeyboardInterrupt:
            print " pressed, stopping the replay..."
        except Exception as error:
            print "-E- {error}".format(error=error)
        finally:
            try:
                log.close()
            except:
                pass
            return rc


if __name__ == "__main__":
    command = GetDevicePerformanceCounters()
    rc = command.main()
    sys.exit(rc)
