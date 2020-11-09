# Copyright (c) 2020 OpenStack Foundation
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


import os
from socket import AF_INET

import ipaddress
import psutil
import sys


OUI = '00,90,69'
MGMNT_NETS_SUBTYPE = 123
SRIOV_MAP_SUBTYPE = 124
COMMAND = 'configure lldp custom-tlv add oui {oui} '\
          + 'subtype {stype} oui-info '
FILE_PATH = '/etc/lldpd.conf'


def set_management_nets_tlv(to_file):
    ifaces = psutil.net_if_addrs()
    iface_addrs = get_ifaces_addr(ifaces)
    management_networks = get_management_networks()
    management_ifaces = calculate_management_ifaces(management_networks,
                                                    iface_addrs)

    mng_ifaces_str = ','.join(management_ifaces)
    if not mng_ifaces_str:
        mng_ifaces_str = 'None'
    command = calculate_command(OUI, MGMNT_NETS_SUBTYPE, mng_ifaces_str)
    if to_file:
        add_to_config(command)
    else:
        execute_command(command)


def get_management_networks():
    try:
        management_networks = os.environ['MANAGEMENT_NETWORKS']
    except KeyError:
        print('Environment variable "MANAGEMENT_NETWORKS" not found')
        return []
    management_networks = management_networks.split(',')
    return management_networks


def calculate_command(oui, stype, data):
    if len(data) > 507:
        raise Exception("Too much data for single TLV")
    if not all(ord(c) < 128 for c in data):
        raise Exception('Data for command contains nonascii characters')

    tlv_data = [ord(i) for i in data]
    tlv_string = ','.join([hex(i) for i in tlv_data])
    tlv_string = tlv_string.replace('0x', '')
    command = COMMAND.format(oui=oui, stype=stype) + tlv_string
    return command


def execute_command(command):
    command = 'lldpcli ' + command
    print('Executing: ' + command)
    exit_code = os.system(command)
    if exit_code != 0:
        raise Exception("Failed to set tlv. Exit code: {}".format(exit_code))


def add_to_config(command):
    with open(FILE_PATH, 'a') as file:
        file.writelines([command + '\n'])


def get_ifaces_addr(ifaces):
    iface_nets = {}

    for iface in ifaces.keys():
        for address in ifaces[iface]:
            if address.family == AF_INET:
                addr = address.address
                iface_nets[iface] = str(addr)

    return iface_nets


def calculate_management_ifaces(management_nets, iface_addrs):
    management_ifaces = []
    management_nets = set(management_nets)

    for iface in iface_addrs.keys():
        iface_net = ipaddress.IPv4Address(iface_addrs[iface])

        if any(iface_net in ipaddress.ip_network(i)
               for i in management_nets):
            management_ifaces.append(iface)

    return management_ifaces


def set_sriov_mappings_tlv(to_file):
    mappings = get_sriov_mappings()
    if len(mappings) == 0:
        return
    command = calculate_command(OUI, SRIOV_MAP_SUBTYPE, mappings)
    if to_file:
        add_to_config(command)
    else:
        execute_command(command)


def get_sriov_mappings():
    try:
        sriov_network_mappings = os.environ['SRIOV_NETWORK_MAPPINGS']
    except KeyError:
        print('Environment variable "SRIOV_NETWORK_MAPPINGS" not found')
        return 'None'
    return sriov_network_mappings


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '-e':
        use_file = False
    else:
        use_file = True

    set_management_nets_tlv(use_file)
    set_sriov_mappings_tlv(use_file)
