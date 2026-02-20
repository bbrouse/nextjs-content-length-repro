export default function Home({ items }) {
  return (
    <div>
      <h1>Next.js Data Compression Test</h1>
      <p>This page returns {items.length} items via getStaticProps.</p>
      <p>
        Check the response headers of the <code>/_next/data/</code> endpoint to
        see whether <code>Content-Length</code> or{" "}
        <code>Transfer-Encoding: chunked</code> is used.
      </p>
    </div>
  );
}

export async function getStaticProps() {
  const items = Array.from({ length: 1000 }, (_, i) => ({
    id: i + 1,
    title: `Item number ${i + 1}`,
    description: `This is a detailed description for item ${i + 1}. It contains enough text to ensure the overall JSON payload is large enough for compression to be meaningful.`,
    category: ["alpha", "beta", "gamma", "delta"][i % 4],
    tags: [`tag-${i % 10}`, `tag-${(i + 3) % 10}`, `tag-${(i + 7) % 10}`],
    metadata: {
      createdAt: "2025-01-15T00:00:00.000Z",
      updatedAt: "2025-06-01T00:00:00.000Z",
      version: ((i % 5) + 1).toString(),
      priority: (i % 3) + 1,
    },
  }));

  return {
    props: { items },
    revalidate: 60,
  };
}
