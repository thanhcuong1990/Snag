import React, {useState} from 'react';
import {
  StatusBar,
  StyleSheet,
  useColorScheme,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
  Image,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';

const TEST_CATEGORIES = {
  CRUD: [
    {name: 'GET Post', id: 'get_post'},
    {name: 'POST Create', id: 'post_create'},
    {name: 'PUT Update', id: 'put_update'},
    {name: 'PATCH Partial', id: 'patch_partial'},
    {name: 'DELETE', id: 'delete_post'},
  ],
  'Image & JSON': [
    {name: 'GET Image', id: 'get_image'},
    {name: 'GET Large JSON', id: 'get_large_json'},
    {name: 'POST Large JSON', id: 'post_large_json'},
    {name: 'Slow Request', id: 'slow_request'},
  ],
  'Auth & Status': [
    {name: 'Auth Bearer', id: 'auth_bearer'},
    {name: '401 Unauthorized', id: 'status_401'},
    {name: '404 Not Found', id: 'status_404'},
    {name: '500 Internal Error', id: 'status_500'},
  ],
  Logs: [
    {name: 'Info Log', id: 'log_info'},
    {name: 'Warn Log', id: 'log_warn'},
    {name: 'Error Log', id: 'log_error'},
  ],
};

function App() {
  const isDarkMode = useColorScheme() === 'dark';

  return (
    <SafeAreaProvider>
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <AppContent />
    </SafeAreaProvider>
  );
}

function AppContent() {
  const safeAreaInsets = useSafeAreaInsets();
  const [responseText, setResponseText] = useState('Tap a test to run');
  const [loading, setLoading] = useState(false);
  const [imageUrl, setImageUrl] = useState<string | null>(null);

  React.useEffect(() => {
    console.log('🚀 Snag Example App launched at ' + new Date().toLocaleTimeString());
    console.info('Tip: You can find all network and log events in the Snag Mac app.');
  }, []);

  const runTest = async (testId: string) => {
    setLoading(true);
    setResponseText('Loading...');
    setImageUrl(null);

    try {
      switch (testId) {
        case 'get_post':
          await performRequest('https://jsonplaceholder.typicode.com/posts/1', 'GET');
          break;
        case 'post_create':
          await performRequest('https://jsonplaceholder.typicode.com/posts', 'POST', {
            title: 'New Post',
            body: 'Hello',
            userId: 1,
          });
          break;
        case 'put_update':
          await performRequest('https://jsonplaceholder.typicode.com/posts/1', 'PUT', {
            id: 1,
            title: 'Updated',
            body: 'Updated',
            userId: 1,
          });
          break;
        case 'patch_partial':
          await performRequest('https://jsonplaceholder.typicode.com/posts/1', 'PATCH', {
            title: 'Partial Update',
          });
          break;
        case 'delete_post':
          await performRequest('https://jsonplaceholder.typicode.com/posts/1', 'DELETE');
          break;
        case 'get_image': {
          const img = `https://picsum.photos/400/300?t=${Date.now()}`;
          const response = await fetch(img);
          const blob = await response.blob();
          const reader = new FileReader();
          reader.onloadend = () => {
            setImageUrl(reader.result as string);
          };
          reader.readAsDataURL(blob);
          setResponseText('GET Image\nStatus: ' + response.status + '\nURL: ' + img);
          break;
        }
        case 'get_large_json':
          await performRequest('https://raw.githubusercontent.com/miloyip/nativejson-benchmark/master/data/citm_catalog.json', 'GET');
          break;
        case 'post_large_json':
          const largeBody: Record<string, string> = {};
          for (let i = 0; i < 50; i++) {
            largeBody['item_' + i] = 'Some data for item ' + i;
          }
          await performRequest('https://httpbin.org/post', 'POST', largeBody);
          break;
        case 'slow_request':
          await performRequest('https://httpbin.org/delay/5', 'GET');
          break;
        case 'auth_bearer':
          await performRequest('https://httpbin.org/bearer', 'GET', null, {
            Authorization: 'Bearer valid-token',
          });
          break;
        case 'status_401':
          await performRequest('https://httpbin.org/status/401', 'GET');
          break;
        case 'status_404':
          await performRequest('https://httpbin.org/status/404', 'GET');
          break;
        case 'status_500':
          await performRequest('https://httpbin.org/status/500', 'GET');
          break;
        case 'log_info':
          console.log('Info log from console.log: ' + new Date().toLocaleTimeString());
          setResponseText('Sent console.log to Snag');
          break;
        case 'log_warn':
          console.warn('Warn log from console.warn: ' + new Date().toLocaleTimeString());
          setResponseText('Sent console.warn to Snag');
          break;
        case 'log_error':
          console.error('Error log from console.error: ' + new Date().toLocaleTimeString());
          setResponseText('Sent console.error to Snag');
          break;
        default:
          setResponseText('Unknown test');
      }
    } catch (e: any) {
      setResponseText('Request failed: ' + e.message);
    } finally {
      setLoading(false);
    }
  };

  const performRequest = async (url: string, method: string, body?: any, headers: any = {}) => {
    const options: RequestInit = {
      method,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'RN-Tester/1.0',
        ...headers,
      },
    };
    if (body) {
      options.body = JSON.stringify(body);
      console.log('Request body:', body);
    }

    const start = Date.now();
    const response = await fetch(url, options);
    const duration = Date.now() - start;
    const data = await response.text();

    let jsonData: any = null;
    if (response.ok && response.headers.get('content-type')?.includes('application/json')) {
      try {
        jsonData = JSON.parse(data);
        console.log('console.log > API Response JSON:', jsonData); // Log JSON object for Snag Mac app
      } catch (e) {
        console.warn('console.warn > Could not parse response as JSON:', e);
      }
    }

    const result = [
      `${method} ${url}`,
      `Status: ${response.status} ${response.statusText}`,
      `Duration: ${duration}ms`,
      '',
      'Headers:',
      JSON.stringify(Object.fromEntries((response.headers as any).entries()), null, 2),
      '',
      'Body:',
      jsonData ? JSON.stringify(jsonData, null, 2) : (data.length > 1000 ? data.substring(0, 1000) + '...' : data),
    ].join('\n');

    setResponseText(result);
  };

  return (
    <View style={styles.container}>
      <View style={[styles.header, {paddingTop: safeAreaInsets.top}]}>
        <Text style={styles.headerTitle}>Snag API Tester</Text>
      </View>

      <ScrollView style={styles.content}>
        {Object.entries(TEST_CATEGORIES).map(([category, tests]) => (
          <View key={category} style={styles.section}>
            <Text style={styles.sectionTitle}>{category}</Text>
            <View style={styles.buttonGrid}>
              {tests.map(test => (
                <TouchableOpacity
                  key={test.id}
                  style={styles.testButton}
                  onPress={() => runTest(test.id)}
                  disabled={loading}>
                  <Text style={styles.buttonText}>{test.name}</Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        ))}

        <View style={styles.responseContainer}>
          <View style={styles.responseHeader}>
            <Text style={styles.responseTitle}>Response</Text>
            {loading && <ActivityIndicator size="small" color="#007AFF" />}
          </View>
          
          <ScrollView style={styles.responseTextContainer} nestedScrollEnabled>
            {imageUrl && (
              <Image source={{uri: imageUrl}} style={styles.previewImage} />
            )}
            <Text style={styles.responseText}>{responseText}</Text>
          </ScrollView>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F2F2F7',
  },
  header: {
    backgroundColor: '#fff',
    paddingBottom: 12,
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: '#E5E5EA',
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    color: '#000',
  },
  content: {
    flex: 1,
  },
  section: {
    marginTop: 20,
    paddingHorizontal: 16,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: '#8E8E93',
    marginBottom: 8,
    textTransform: 'uppercase',
  },
  buttonGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginHorizontal: -4,
  },
  testButton: {
    backgroundColor: '#fff',
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 12,
    margin: 4,
    minWidth: '47%',
    borderWidth: 1,
    borderColor: '#E5E5EA',
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 1},
    shadowOpacity: 0.05,
    shadowRadius: 2,
    elevation: 1,
  },
  buttonText: {
    fontSize: 14,
    color: '#007AFF',
    fontWeight: '500',
  },
  responseContainer: {
    margin: 16,
    marginTop: 24,
    paddingBottom: 40,
  },
  responseHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  responseTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: '#000',
  },
  responseTextContainer: {
    backgroundColor: '#fff',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#E5E5EA',
    minHeight: 200,
    maxHeight: 400,
  },
  responseText: {
    padding: 12,
    fontSize: 12,
    fontFamily: 'Menlo',
    color: '#333',
  },
  previewImage: {
    width: '100%',
    height: 200,
    borderTopLeftRadius: 12,
    borderTopRightRadius: 12,
    backgroundColor: '#eee',
  },
});

export default App;
