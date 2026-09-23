import io.anserini.index.IndexReaderUtils;
import java.io.BufferedOutputStream;
import java.io.BufferedWriter;
import java.io.Closeable;
import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.apache.lucene.index.IndexReader;
import org.apache.lucene.index.MultiTerms;
import org.apache.lucene.index.PostingsEnum;
import org.apache.lucene.index.Terms;
import org.apache.lucene.index.TermsEnum;
import org.apache.lucene.util.BytesRef;

/**
 * Builds the raw BM25Tree Stage-1 and Stage-2 databases directly from a Lucene
 * index.  A single postings pass builds Stage 1 and every requested Stage-2
 * sub-block size for one (B, r) pair.
 *
 * <p>The output is intentionally pre-Cuckoo.  It is byte-compatible with the
 * Python builders: Stage-1 rows contain r uint8 scores, Stage-2 rows contain
 * B/s uint8 scores, and every ID-map record is the little-endian tuple
 * (term_id:uint32, node_id:uint32, row_index:uint64).</p>
 */
public final class BuildPirDatabases {
  private static final String FIELD = "contents";
  private static final int BUFFER_BYTES = 8 * 1024 * 1024;

  private static final class Options {
    Path index;
    Path output;
    int blockSize;
    int fanout;
    int[] subblockSizes;
    double scale = 10.0;
    double k1 = 0.9;
    double b = 0.4;
    int progressEvery = 100_000;
  }

  private static final class IntVector {
    private int[] values = new int[16];
    private int size;

    void add(int value) {
      if (size == values.length) {
        values = Arrays.copyOf(values, values.length * 2);
      }
      values[size++] = value;
    }

    int get(int index) {
      return values[index];
    }

    int size() {
      return size;
    }
  }

  private static final class CountingOutput implements Closeable {
    private final OutputStream stream;
    private long bytes;

    CountingOutput(Path path) throws IOException {
      Files.createDirectories(path.getParent());
      stream = new BufferedOutputStream(
          Files.newOutputStream(path, StandardOpenOption.CREATE,
              StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE),
          BUFFER_BYTES);
    }

    void writeByte(int value) throws IOException {
      stream.write(value);
      bytes++;
    }

    void write(byte[] value) throws IOException {
      stream.write(value);
      bytes += value.length;
    }

    void writeIntLE(int value) throws IOException {
      writeByte(value);
      writeByte(value >>> 8);
      writeByte(value >>> 16);
      writeByte(value >>> 24);
    }

    void writeLongLE(long value) throws IOException {
      writeByte((int) value);
      writeByte((int) (value >>> 8));
      writeByte((int) (value >>> 16));
      writeByte((int) (value >>> 24));
      writeByte((int) (value >>> 32));
      writeByte((int) (value >>> 40));
      writeByte((int) (value >>> 48));
      writeByte((int) (value >>> 56));
    }

    long bytes() {
      return bytes;
    }

    @Override
    public void close() throws IOException {
      stream.close();
    }
  }

  private static final class Outputs implements Closeable {
    final CountingOutput stage1Data;
    final CountingOutput stage1IdMap;
    final CountingOutput stage2IdMap;
    final LinkedHashMap<Integer, CountingOutput> stage2Data = new LinkedHashMap<>();
    final BufferedWriter vocabulary;
    long stage1Rows;
    long stage2Rows;
    boolean firstVocabularyTerm = true;

    Outputs(Options options) throws IOException {
      Files.createDirectories(options.output);
      stage1Data = new CountingOutput(options.output.resolve("stage1_data.bin"));
      stage1IdMap = new CountingOutput(options.output.resolve("stage1_idmap.bin"));
      stage2IdMap = new CountingOutput(options.output.resolve("stage2_idmap.bin"));
      for (int subblock : options.subblockSizes) {
        stage2Data.put(subblock,
            new CountingOutput(options.output.resolve("stage2_s" + subblock).resolve("data.bin")));
      }
      vocabulary = new BufferedWriter(new OutputStreamWriter(
          Files.newOutputStream(options.output.resolve("stage1_vocab.json"),
              StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING,
              StandardOpenOption.WRITE),
          StandardCharsets.UTF_8), BUFFER_BYTES);
      vocabulary.write('{');
    }

    void writeVocabularyTerm(String term, int termId) throws IOException {
      if (!firstVocabularyTerm) {
        vocabulary.write(',');
        vocabulary.write(' ');
      }
      firstVocabularyTerm = false;
      writeJsonString(vocabulary, term);
      vocabulary.write(": ");
      vocabulary.write(Integer.toString(termId));
    }

    void writeStage1Id(int termId, int nodeId) throws IOException {
      stage1IdMap.writeIntLE(termId);
      stage1IdMap.writeIntLE(nodeId);
      stage1IdMap.writeLongLE(stage1Rows++);
    }

    void writeStage2Id(int termId, int nodeId) throws IOException {
      stage2IdMap.writeIntLE(termId);
      stage2IdMap.writeIntLE(nodeId);
      stage2IdMap.writeLongLE(stage2Rows++);
    }

    @Override
    public void close() throws IOException {
      IOException failure = null;
      try {
        vocabulary.write('}');
        vocabulary.close();
      } catch (IOException e) {
        failure = e;
      }
      List<Closeable> streams = new ArrayList<>();
      streams.add(stage1Data);
      streams.add(stage1IdMap);
      streams.add(stage2IdMap);
      streams.addAll(stage2Data.values());
      for (Closeable stream : streams) {
        try {
          stream.close();
        } catch (IOException e) {
          if (failure == null) failure = e;
        }
      }
      if (failure != null) throw failure;
    }
  }

  private static void writeJsonString(BufferedWriter writer, String value) throws IOException {
    writer.write('"');
    for (int i = 0; i < value.length(); i++) {
      char c = value.charAt(i);
      switch (c) {
        case '"': writer.write("\\\""); break;
        case '\\': writer.write("\\\\"); break;
        case '\b': writer.write("\\b"); break;
        case '\f': writer.write("\\f"); break;
        case '\n': writer.write("\\n"); break;
        case '\r': writer.write("\\r"); break;
        case '\t': writer.write("\\t"); break;
        default:
          if (c < 0x20) {
            writer.write(String.format("\\u%04x", (int) c));
          } else {
            writer.write(c);
          }
      }
    }
    writer.write('"');
  }

  private static int integerPower(int base, int exponent) {
    int value = 1;
    for (int i = 0; i < exponent; i++) value = Math.multiplyExact(value, base);
    return value;
  }

  private static int treeHeight(int documents, int blockSize, int fanout) {
    long leaves = (documents + (long) blockSize - 1L) / blockSize;
    int height = 0;
    long capacity = 1;
    while (capacity < leaves) {
      capacity = Math.multiplyExact(capacity, fanout);
      height++;
    }
    return height;
  }

  private static double inverseDocumentFrequency(int documentFrequency, int documents) {
    return Math.log(1.0 + (documents - documentFrequency + 0.5)
        / (documentFrequency + 0.5));
  }

  private static double bm25(int tf, int documentLength, double averageLength,
                             double k1, double b) {
    double numerator = (k1 + 1.0) * tf;
    double denominator = tf + k1 * (1.0 - b + b * documentLength
        / Math.max(1.0, averageLength));
    return numerator / Math.max(1e-9, denominator);
  }

  private static int quantizeStage1(int tf, double idf, int documentLength,
                                    double averageLength, Options options) {
    float score = (float) (bm25(tf, documentLength, averageLength, options.k1, options.b) * idf);
    float scaled = (float) (score * options.scale);
    return Math.max(0, Math.min(255, (int) Math.rint(scaled)));
  }

  private static int quantizeStage2(int tf, double idf, int documentLength,
                                    double averageLength, Options options) {
    double scaled = bm25(tf, documentLength, averageLength, options.k1, options.b)
        * idf * options.scale;
    return Math.max(0, Math.min(255, (int) Math.rint(scaled)));
  }

  private static void writeStage1Rows(
      int termId, double idf, IntVector childIndices, IntVector childTfs,
      int height, int defaultLength, double averageLength, Options options,
      Outputs outputs) throws IOException {
    for (int level = height - 1; level >= 0; level--) {
      IntVector parentIndices = new IntVector();
      IntVector parentTfs = new IntVector();
      int offset = 0;
      while (offset < childIndices.size()) {
        int parentIndex = childIndices.get(offset) / options.fanout;
        byte[] row = new byte[options.fanout];
        int parentMaxTf = 0;
        while (offset < childIndices.size()
            && childIndices.get(offset) / options.fanout == parentIndex) {
          int tf = childTfs.get(offset);
          int childPosition = childIndices.get(offset) % options.fanout;
          row[childPosition] = (byte) quantizeStage1(
              tf, idf, defaultLength, averageLength, options);
          parentMaxTf = Math.max(parentMaxTf, tf);
          offset++;
        }
        outputs.stage1Data.write(row);
        outputs.writeStage1Id(termId, integerPower(options.fanout, level) + parentIndex);
        parentIndices.add(parentIndex);
        parentTfs.add(parentMaxTf);
      }
      childIndices = parentIndices;
      childTfs = parentTfs;
    }
  }

  private static void writeStage2Row(
      int termId, int leafIndex, int[] baseMaxTfs, double idf, int height,
      int defaultLength, double averageLength, Options options, Outputs outputs)
      throws IOException {
    int leafNode = integerPower(options.fanout, height) + leafIndex;
    outputs.writeStage2Id(termId, leafNode);
    int baseSubblock = options.subblockSizes[0];
    for (Map.Entry<Integer, CountingOutput> entry : outputs.stage2Data.entrySet()) {
      int subblock = entry.getKey();
      int grouping = subblock / baseSubblock;
      int columns = options.blockSize / subblock;
      byte[] row = new byte[columns];
      for (int column = 0; column < columns; column++) {
        int maxTf = 0;
        int start = column * grouping;
        for (int j = 0; j < grouping; j++) {
          maxTf = Math.max(maxTf, baseMaxTfs[start + j]);
        }
        row[column] = (byte) quantizeStage2(
            maxTf, idf, defaultLength, averageLength, options);
      }
      entry.getValue().write(row);
    }
  }

  private static void build(Options options) throws Exception {
    try (IndexReader reader = IndexReaderUtils.getReader(options.index.toString());
         Outputs outputs = new Outputs(options)) {
      int documents = reader.maxDoc();
      long totalTerms = reader.getSumTotalTermFreq(FIELD);
      double averageLength = totalTerms / (double) Math.max(1, documents);
      // Match the reference builders: Stage 1 truncates avgdl while Stage 2
      // rounds it to the nearest integer.
      int stage1DefaultLength = (int) averageLength;
      int stage2DefaultLength = (int) Math.rint(averageLength);
      int height = treeHeight(documents, options.blockSize, options.fanout);
      int baseSubblock = options.subblockSizes[0];
      int baseColumns = options.blockSize / baseSubblock;

      System.out.printf(
          "Index N=%d avgdl=%.6f B=%d r=%d height=%d s=%s output=%s%n",
          documents, averageLength, options.blockSize, options.fanout, height,
          Arrays.toString(options.subblockSizes), options.output);

      Terms terms = MultiTerms.getTerms(reader, FIELD);
      if (terms == null) throw new IOException("index has no field '" + FIELD + "'");
      TermsEnum iterator = terms.iterator();
      BytesRef termBytes;
      int termId = 0;
      long started = System.nanoTime();
      while ((termBytes = iterator.next()) != null) {
        String term = termBytes.utf8ToString();
        outputs.writeVocabularyTerm(term, termId);
        int documentFrequency = iterator.docFreq();
        double idf = inverseDocumentFrequency(documentFrequency, documents);
        PostingsEnum postings = iterator.postings(null, PostingsEnum.FREQS);

        IntVector leafIndices = new IntVector();
        IntVector leafTfs = new IntVector();
        int currentLeaf = -1;
        int currentLeafMaxTf = 0;
        int[] baseMaxTfs = new int[baseColumns];

        for (int document = postings.nextDoc();
             document != PostingsEnum.NO_MORE_DOCS;
             document = postings.nextDoc()) {
          int leaf = document / options.blockSize;
          if (leaf != currentLeaf) {
            if (currentLeaf >= 0) {
              writeStage2Row(termId, currentLeaf, baseMaxTfs, idf, height,
                  stage2DefaultLength, averageLength, options, outputs);
              leafIndices.add(currentLeaf);
              leafTfs.add(currentLeafMaxTf);
              Arrays.fill(baseMaxTfs, 0);
            }
            currentLeaf = leaf;
            currentLeafMaxTf = 0;
          }
          int tf = postings.freq();
          int withinLeaf = document % options.blockSize;
          int baseColumn = withinLeaf / baseSubblock;
          baseMaxTfs[baseColumn] = Math.max(baseMaxTfs[baseColumn], tf);
          currentLeafMaxTf = Math.max(currentLeafMaxTf, tf);
        }
        if (currentLeaf >= 0) {
          writeStage2Row(termId, currentLeaf, baseMaxTfs, idf, height,
              stage2DefaultLength, averageLength, options, outputs);
          leafIndices.add(currentLeaf);
          leafTfs.add(currentLeafMaxTf);
        }

        writeStage1Rows(termId, idf, leafIndices, leafTfs, height,
            stage1DefaultLength, averageLength, options, outputs);
        termId++;
        if (options.progressEvery > 0 && termId % options.progressEvery == 0) {
          double seconds = (System.nanoTime() - started) / 1e9;
          System.out.printf(
              "terms=%d stage1_rows=%d stage2_rows=%d elapsed=%.1fs%n",
              termId, outputs.stage1Rows, outputs.stage2Rows, seconds);
        }
      }

      writeLayout(options.output.resolve("layout.json"), documents,
          options.blockSize, options.fanout);
      double seconds = (System.nanoTime() - started) / 1e9;
      System.out.printf(
          "Done: terms=%d stage1_rows=%d stage2_rows=%d elapsed=%.1fs%n",
          termId, outputs.stage1Rows, outputs.stage2Rows, seconds);
    }
  }

  private static void writeLayout(Path path, int documents, int blockSize, int fanout)
      throws IOException {
    String json = String.format(
        "{\n  \"N\": %d,\n  \"B\": %d,\n  \"r\": %d,\n  \"min_dl_map\": {}\n}\n",
        documents, blockSize, fanout);
    Files.writeString(path, json, StandardCharsets.UTF_8,
        StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING,
        StandardOpenOption.WRITE);
  }

  private static Options parse(String[] arguments) {
    Options options = new Options();
    for (int i = 0; i < arguments.length; i++) {
      String name = arguments[i];
      if (i + 1 >= arguments.length) throw new IllegalArgumentException("missing value for " + name);
      String value = arguments[++i];
      switch (name) {
        case "--index": options.index = Path.of(value); break;
        case "--output": options.output = Path.of(value); break;
        case "--B": options.blockSize = Integer.parseInt(value); break;
        case "--r": options.fanout = Integer.parseInt(value); break;
        case "--s":
          options.subblockSizes = Arrays.stream(value.split(","))
              .mapToInt(Integer::parseInt).sorted().toArray();
          break;
        case "--scale": options.scale = Double.parseDouble(value); break;
        case "--k1": options.k1 = Double.parseDouble(value); break;
        case "--b": options.b = Double.parseDouble(value); break;
        case "--progress-every": options.progressEvery = Integer.parseInt(value); break;
        default: throw new IllegalArgumentException("unknown option: " + name);
      }
    }
    if (options.index == null || options.output == null || options.blockSize <= 0
        || options.fanout <= 1 || options.subblockSizes == null
        || options.subblockSizes.length == 0) {
      throw new IllegalArgumentException(
          "required: --index PATH --output PATH --B INT --r INT --s INT[,INT...]");
    }
    int smallest = options.subblockSizes[0];
    for (int subblock : options.subblockSizes) {
      if (subblock <= 0 || options.blockSize % subblock != 0
          || subblock % smallest != 0) {
        throw new IllegalArgumentException(
            "each s must divide B and be a multiple of the smallest s");
      }
    }
    return options;
  }

  public static void main(String[] arguments) throws Exception {
    try {
      build(parse(arguments));
    } catch (IllegalArgumentException e) {
      System.err.println(e.getMessage());
      System.exit(2);
    }
  }
}
