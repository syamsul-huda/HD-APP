import base64, hashlib, os, sys
from cryptography.fernet import Fernet

password = os.environ.get('KEYSTORE_PASSWORD', '')
if not password:
    print('ERROR: KEYSTORE_PASSWORD not set')
    sys.exit(1)

key = base64.urlsafe_b64encode(hashlib.sha256(password.encode()).digest())
enc_data = open('android/app/release.keystore.enc', 'rb').read()
data = Fernet(key).decrypt(enc_data)
open('android/app/release.keystore', 'wb').write(data)
print('Keystore decrypted:', len(data), 'bytes, valid:', data[0] == 0x30)
