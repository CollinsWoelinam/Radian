import ConsoleLoader from "./ConsoleLoader";

export default function ConsoleLayout({ children }: { children: React.ReactNode }) {
  return <ConsoleLoader>{children}</ConsoleLoader>;
}
