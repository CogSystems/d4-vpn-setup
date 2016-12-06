#!/bin/sh

make_key()
{
    local name=$1
    local make_p12=${2:-0}

    # Generate a new key pair for this peer
    ipsec pki --gen --type rsa --size 2048 --outform pem > private/${name}-key.pem
    chmod 600 private/${name}-key.pem

    # We now certify the new peer public key.

    # public key host certificate.
    # The hostname or ip address must be in either the DN (--dn) or Alt Name
    #  (--san) fields of the certificate.

    # Extract the public key from the pair we just generated, send this to issueing task.
    # Issue a certificate that says peer public key + peer identity are matched.
    # Use the CA private key to sign the certificate.
    # The CA's own cert is referenced in the newly issued certificate.
    ipsec pki --pub --in private/${name}-key.pem --type rsa | \
        ipsec pki --issue --lifetime 730 --cacert cacerts/ca-cert.pem \
            --cakey private/ca-key.pem \
            --dn "C=NET, O=Cog Systems Customer, CN=${name}" \
            --san ${name} \
            --flag serverAuth --flag ikeIntermediate \
            --outform pem > certs/${name}-cert.pem

    if [ ${make_p12} -ne 0 ]; then
        openssl pkcs12 -export -inkey private/${name}-key.pem \
                -in certs/${name}-cert.pem -name "${name} VPN Certificate" \
                -certfile cacerts/ca-cert.pem \
                -caname "Cog Systems Customer Test Root CA" \
                -out certs/${name}.p12
    fi
}

make_ca()
{
    # Generate a new CA key pair
    ipsec pki --gen --type rsa --size 4096 --outform pem > private/ca-key.pem
    chmod 600 private/ca-key.pem
    # Use the CA private key to self-sign a certificate of the CA public key + CA identity.
    ipsec pki --self --ca --lifetime 3650 --in private/ca-key.pem --type rsa \
        --dn "C=NET, O=Cog Systems Customer, CN=Cog Systems Customer Test Root CA" \
        --outform pem > cacerts/ca-cert.pem
}

usage()
{
	echo "USAGE:"
	echo $0 "make_ca=[1:0] keys=8"
}

if [ ! -d etc/ipsec.d ]; then
    mkdir -p etc/ipsec.d
    chmod 0755 etc/ipsec.d
fi

cd etc/ipsec.d
for d in aacerts acerts cacerts certs crls ocspcerts policies reqs; do
    if [ ! -d $d ]; then
        mkdir $d
        chmod 0755 $d
    fi
done

if [ ! -d private ]; then
    mkdir private
    chmod 0700 private
fi

MAKE_CA=0
KEY_COUNT=8

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        make_ca)
            MAKE_CA=$VALUE
            ;;
        keys)
            KEY_COUNT=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

# Create a Certificate Authorithy key and self signed certificate
if [ $MAKE_CA -eq 1 ]; then
    make_ca

    # Create the external vpn server cert and key
    make_key d4.cust.cogsecure.com
fi

if [ ! -f private/ca-key.pem ]; then
    echo "NO CA FOUND!"
    usage
    exit
fi

# Create internal certs and keys for each peer
for n in $(seq 1 $KEY_COUNT); do
    # support up to four barers per device
    make_key client${n}-con1.cust.d4
    make_key client${n}-con2.cust.d4
    make_key client${n}-con3.cust.d4
    make_key client${n}-con4.cust.d4
done
