import { Suspense } from "react";
import JobsPage from "@/console/pages/JobsPage";

export default function Page() {
  return (
    <Suspense>
      <JobsPage />
    </Suspense>
  );
}
