#!/usr/bin/env python
#
#    Copyright 2016 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

import glob
import logging
import os
import pyinotify
import sys

from pyinotify import WatchManager, Notifier, ProcessEvent, ALL_EVENTS

try:  # Python 2.7+
    from logging import NullHandler
except ImportError:
    class NullHandler(logging.Handler):
        def emit(self, record):
            pass
from logging.config import fileConfig

# Command line usage
def usage():
    h = """
    Watch a directory for YAML alarm configuration file changes

    Usage: {} <DIRECTORY>

    """
    print(h.format(sys.argv[0]))

# Logging initialization
def logger_init(name):
    """Initialize logger instance."""
    log = logging.getLogger()
    try:
        fileConfig('/etc/stacklight/alarming/config/alarm-manager.ini')
    except Exception as e:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(
            logging.Formatter("[%(asctime)s.%(msecs)03d %(name)s %(levelname)s] %(message)s",
                "%Y-%m-%d %H:%M:%S"))
        log.addHandler(console_handler)
        log.setLevel(logging.DEBUG)
    return log

class DebugAllEvents(ProcessEvent):
    """
    Dummy class used to print events strings representations. For instance this
    class is used from command line to print all received events to stdout.
    """
    def my_init(self, out=None):
        """
        @param out: Logger where events will be written.
        @type out: Object providing a valid logging object interface.
        """
        if out is None:
            global log
            out = log
        self._out = out

    def process_default(self, event):
        """
        Writes event string representation to logging object provided to
        my_init().

        @param event: Event to be processed. Can be of any type of events but
                      IN_Q_OVERFLOW events (see method process_IN_Q_OVERFLOW).
        @type event: Event instance
        """
        self._out.debug(str(event))

# Main procedure call
def _main():
    global log
    if len(sys.argv) != 2:
        usage()
        sys.exit(1)
    arg = sys.argv[1]
    if os.path.isdir(arg):
        path = arg
    else:
        print("'{}' no such directory".format(arg))
        usage()
        sys.exit(1)
    # watch manager instance
    wm = WatchManager()
    # notifier instance and init
    notifier = Notifier(wm, default_proc_fun=DebugAllEvents())
    # What mask to apply
    mask = ALL_EVENTS
    log.debug('Start monitoring of %s' % path)
    wm.add_watch(path, mask, rec=False, auto_add=False, do_glob=False)
    # Loop forever (until sigint signal get caught)
    notifier.loop(callback=None)

log = logger_init(__name__)
if __name__ == '__main__':
    _main()

