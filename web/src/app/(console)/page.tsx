import { Suspense } from "react";
import LivePage from "@/console/pages/LivePage";

export default function Page() {
  return (
    <Suspense>
      <LivePage />
    </Suspense>
  );
}
