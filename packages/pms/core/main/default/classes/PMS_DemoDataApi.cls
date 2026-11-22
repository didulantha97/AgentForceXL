/**
 * Entry point for scripts (scripts/pms-package.sh demo-data). Anonymous Apex cannot call a public class of a
 * packaged namespace, so this is the one global class: a System.Callable that hands over to PMS_DemoData.
 * It adds no behaviour and no checks of its own; PMS_DemoData applies the production, admin and licence guards.
 *
 *   Callable api = (Callable) Type.forName(namespaceOrNull, 'PMS_DemoDataApi').newInstance();
 *   api.call('load', new Map<String, Object>{ 'pack' => 'baseline' });   // also 'reset', 'status'
 *
 * Output goes to the debug log as lines starting with PMS_DEMO| so the script can read them.
 */
global with sharing class PMS_DemoDataApi implements System.Callable {
  global Object call(String action, Map<String, Object> args) {
    String pack = args != null &&
      args.get('pack') != null
      ? String.valueOf(args.get('pack'))
      : null;
    switch on action {
      when 'load' {
        String message = PMS_DemoData.load(pack);
        System.debug('PMS_DEMO|message|' + message);
        return message;
      }
      when 'reset' {
        String message = PMS_DemoData.reset(pack);
        System.debug('PMS_DEMO|message|' + message);
        return message;
      }
      when 'status' {
        PMS_DemoData.Status st = PMS_DemoData.status();
        System.debug(
          'PMS_DEMO|status|allowed=' +
            st.allowed +
            '|busy=' +
            st.busy +
            '|total=' +
            st.total +
            '|' +
            (st.reason == null ? '' : st.reason)
        );
        for (PMS_DemoData.PackInfo p : st.packs) {
          System.debug(
            'PMS_DEMO|pack|' +
              p.key +
              '|' +
              p.state +
              '|' +
              p.records +
              '|' +
              (p.message == null ? '' : p.message)
          );
        }
        return st.busy;
      }
      when else {
        throw new PMS_DemoData.DemoException(
          'Unknown demo data action: ' + action
        );
      }
    }
  }
}
