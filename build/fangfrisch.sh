#!/usr/bin/env bash
python3 -m venv /usr/local/share/fangfrisch-venv
source /usr/local/share/fangfrisch-venv/bin/activate
pip install --upgrade pip
pip install fangfrisch
ln -s /usr/local/share/fangfrisch-venv/bin/fangfrisch /usr/local/bin/fangfrisch
deactivate
