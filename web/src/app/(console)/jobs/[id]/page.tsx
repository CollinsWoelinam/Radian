import { Suspense } from "react";
import DispatchPage from "@/console/pages/DispatchPage";

export default function Page() {
  return (
    <Suspense>
      <DispatchPage />
    </Suspense>
  );
}
