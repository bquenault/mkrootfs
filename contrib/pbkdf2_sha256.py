#!/usr/bin/env python
from sys import argv
import django.contrib.auth.hashers
if argv.__len__() == 2:
  print make_password(argv[1])
