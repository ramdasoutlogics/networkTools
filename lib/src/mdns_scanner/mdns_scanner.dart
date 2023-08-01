import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_tools/network_tools.dart';
import 'package:network_tools/src/mdns_scanner/get_srv_list_by_os/srv_list.dart';
import 'package:network_tools/src/mdns_scanner/list_of_srv_records.dart';
import 'package:network_tools/src/network_tools_utils.dart';
import 'package:universal_io/io.dart';

class MdnsScanner {
  /// This method searching for all the mdns devices in the network.
  /// TODO: The implementation is **Lacking!** and will not find all the
  /// TODO: results that actual exist in the network!, only some of them.
  /// TODO: This is because missing functionality in dart
  /// TODO: https://github.com/flutter/flutter/issues/97210
  /// TODO: In some cases we resolve this missing functionality using
  /// TODO: specific os tools.

  static Future<List<ActiveHost>> searchMdnsDevices({
    bool forceUseOfSavedSrvRecordList = false,
  }) async {
    List<String> srvRecordListToSearchIn;

    if (forceUseOfSavedSrvRecordList) {
      srvRecordListToSearchIn = tcpSrvRecordsList;
      srvRecordListToSearchIn.addAll(udpSrvRecordsList);
    } else {
      final List<String>? srvRecordsFromOs = await SrvList.getSrvRecordList();

      if (srvRecordsFromOs == null || srvRecordsFromOs.isEmpty) {
        srvRecordListToSearchIn = tcpSrvRecordsList;
        srvRecordListToSearchIn.addAll(udpSrvRecordsList);
      } else {
        srvRecordListToSearchIn = srvRecordsFromOs;
      }
    }

    final List<Future<List<ActiveHost>>> activeHostListsFuture = [];
    for (final String srvRecord in srvRecordListToSearchIn) {
      activeHostListsFuture.add(findingMdnsWithAddress(srvRecord));
    }

    final List<ActiveHost> activeHostList = [];

    for (final Future<List<ActiveHost>> activeHostListFuture
        in activeHostListsFuture) {
      activeHostList.addAll(await activeHostListFuture);
    }

    return activeHostList;
  }

  static Future<List<ActiveHost>> findingMdnsWithAddress(
    String serviceType,
  ) async {
    final List<MdnsInfo> mdnsFoundList = [];

    final MDnsClient client = MDnsClient(
      rawDatagramSocketFactory: (
        dynamic host,
        int port, {
        bool? reuseAddress,
        bool? reusePort,
        int? ttl,
      }) {
        return RawDatagramSocket.bind(
          host,
          port,
          reusePort: !Platform.isWindows && !Platform.isAndroid,
          ttl: ttl!,
        );
      },
    );

    await client.start();

    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceType),
    )) {
      await for (final SrvResourceRecord srv
          in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      )) {
        final MdnsInfo mdnsFound = MdnsInfo(
          srvResourceRecord: srv,
          ptrResourceRecord: ptr,
        );
        mdnsFoundList.add(mdnsFound);
      }
    }
    client.stop();

    final List<ActiveHost> listOfActiveHost = [];
    for (final MdnsInfo foundMdns in mdnsFoundList) {
      final List<InternetAddress>? internetAddressList;
      try {
        internetAddressList =
            await InternetAddress.lookup(foundMdns.mdnsSrvTarget);

        // There can be multiple devices with the same name
        for (final InternetAddress internetAddress in internetAddressList) {
          final ActiveHost tempHost = ActiveHost(
            internetAddress: internetAddress,
            mdnsInfoVar: foundMdns,
          );
          listOfActiveHost.add(tempHost);
        }
      } catch (e) {
        log.severe(
          'Error finding ip of mdns record ${foundMdns.ptrResourceRecord.name} srv target ${foundMdns.mdnsSrvTarget}, will add it with ip 0.0.0.0\n$e',
        );
        final ActiveHost tempHost = ActiveHost(
          internetAddress: InternetAddress('0.0.0.0'),
          mdnsInfoVar: foundMdns,
        );
        listOfActiveHost.add(tempHost);
      }
    }

    return listOfActiveHost;
  }
}
