#!/usr/bin/env python3

import random
import string

nonce_length = 15

nonce = ''.join(random.choices(string.ascii_letters + string.digits, k=nonce_length))

print(nonce)
