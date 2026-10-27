import { Suspense } from "react";
import ZonesPage from "@/console/pages/ZonesPage";

export default function Page() {
  return (
    <Suspense>
      <ZonesPage />
    </Suspense>
  );
}
