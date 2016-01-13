require 'base64'
require 'json'
require 'openssl'
require 'securerandom'

require 'jwe/base64'
require 'jwe/serialization/compact'
require 'jwe/alg'
require 'jwe/enc'
require 'jwe/zip'

module JWE
  class DecodeError < Exception; end
  class NotImplementedError < Exception; end
  class BadCEK < Exception; end
  class InvalidData < Exception; end

  VALID_ALG = [ 'RSA1_5', 'RSA-OAEP', 'RSA-OAEP-256', 'A128KW' 'A192KW', 'A256KW', 'dir', 'ECDH-ES', 'ECDH-ES+A128KW', 'ECDH-ES+A192KW', 'ECDH-ES+A256KW', 'A128GCMKW', 'A192GCMKW', 'A256GCMKW', 'PBES2-HS256+A128KW', 'PBES2-HS384+A192KW', 'PBES2-HS512+A256KW' ]
  VALID_ENC = [ 'A128CBC-HS256', 'A192CBC-HS384', 'A256CBC-HS512', 'A128GCM', 'A192GCM', 'A256GCM' ]
  VALID_ZIP = [ 'DEF' ]

  def self.encrypt(payload, key, alg: 'RSA-OAEP', enc: 'A128GCM', zip: nil)
    raise ArgumentError.new("\"#{alg}\" is not a valid alg method") unless VALID_ALG.include?(alg)
    raise ArgumentError.new("\"#{enc}\" is not a valid enc method") unless VALID_ENC.include?(enc)
    raise ArgumentError.new("\"#{zip}\" is not a valid zip method") unless zip.nil? || zip == '' || VALID_ZIP.include?(zip)

    header = { alg: alg, enc: enc }
    header[:zip] = zip if zip and zip != ''

    cipher = Enc.for(enc).new
    cipher.cek = key if alg == 'dir'

    if zip and zip != ''
      payload = Zip.for(zip).new.compress(payload)
    end

    ciphertext = cipher.encrypt(payload, Base64::jwe_encode(header.to_json))
    encrypted_cek = Alg.for(alg).new(key).encrypt(cipher.cek)

    Serialization::Compact.encode(header.to_json, encrypted_cek, cipher.iv, ciphertext, cipher.tag)
  end

  def self.decrypt(payload, key)
    header, enc_key, iv, ciphertext, tag = Serialization::Compact.decode(payload)
    header = JSON.parse(header)
    base64header = payload.split('.').first

    raise ArgumentError.new("\"#{header['alg']}\" is not a valid alg method") unless VALID_ALG.include?(header['alg'])
    raise ArgumentError.new("\"#{header['enc']}\" is not a valid enc method") unless VALID_ENC.include?(header['enc'])
    raise ArgumentError.new("\"#{header['zip']}\" is not a valid zip method") unless header['zip'].nil? || VALID_ZIP.include?(header['zip'])

    cek = Alg.for(header['alg']).new(key).decrypt(enc_key)
    cipher = Enc.for(header['enc']).new(cek, iv)
    cipher.tag = tag

    plaintext = cipher.decrypt(ciphertext, base64header)

    if header['zip']
      Zip.for(header['zip']).new.decompress(plaintext)
    else
      plaintext
    end
  end
end
