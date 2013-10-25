#!/bin/bash

killall update-notifier
kdeinit4 --suicide
sudo killall update-manager
sudo killall update-notifier
